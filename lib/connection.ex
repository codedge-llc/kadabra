defmodule Kadabra.Connection do
  @moduledoc false

  defstruct ref: nil,
            buffer: "",
            client: nil,
            uri: nil,
            scheme: :https,
            opts: [],
            socket: nil,
            streams: MapSet.new,
            reconnect: true,
            flow_control: nil

  use GenServer
  require Logger

  alias Kadabra.{Connection, ConnectionSettings, Encodable, Error,
    Frame, Hpack, Http2, Stream}
  alias Kadabra.Frame.{Continuation, Data, Goaway, Headers, Ping,
    PushPromise, RstStream, WindowUpdate}

  @type t :: %__MODULE__{
    buffer: binary,
    client: pid,
    flow_control: term,
    opts: Keyword.t,
    reconnect: boolean,
    ref: nil,
    scheme: :https,
    streams: MapSet.new,
    socket: sock,
    uri: charlist
  }

  @type sock :: {:sslsocket, any, pid | {any, any}}

  @type frame :: Data.t
               | Headers.t
               | RstStream.t
               | Frame.Settings.t
               | PushPromise.t
               | Ping.t
               | Goaway.t
               | WindowUpdate.t
               | Continuation.t

  @data 0x0
  @headers 0x1
  @rst_stream 0x3
  @settings 0x4
  @push_promise 0x5
  @ping 0x6
  @goaway 0x7
  @window_update 0x8
  @continuation 0x9

  def start_link(uri, pid, opts \\ []) do
    GenServer.start_link(__MODULE__, {:ok, uri, pid, opts})
  end

  def init({:ok, uri, pid, opts}) do
    case Connection.Ssl.connect(uri, opts) do
      {:ok, socket} ->
        send_preface_and_settings(socket)
        state = initial_state(socket, uri, pid, opts)
        {:ok, state}
      {:error, error} ->
        Logger.error(inspect(error))
        {:error, error}
    end
  end

  defp initial_state(socket, uri, pid, opts) do
   ref = :erlang.make_ref
   Kadabra.Supervisor.start_settings(ref)
   Kadabra.Supervisor.start_decoder(ref)
   Kadabra.Supervisor.start_encoder(ref)

   %__MODULE__{
      ref: ref,
      client: pid,
      uri: uri,
      scheme: opts[:scheme] || :https,
      opts: opts,
      socket: socket,
      reconnect: opts[:reconnect],
      flow_control: %Kadabra.Connection.FlowControl{}
    }
  end

  defp send_preface_and_settings(socket) do
    :ssl.send(socket, Http2.connection_preface)
    bin =
      %Frame.Settings{settings: Connection.Settings.default}
      |> Encodable.to_bin
    :ssl.send(socket, bin)
  end

  # handle_cast

  def handle_cast({:send, :headers, headers}, state) do
    new_state = do_send_headers(headers, nil, state)
    {:noreply, new_state}
  end

  def handle_cast({:send, :headers, headers, payload}, state) do
    new_state = do_send_headers(headers, payload, state)
    {:noreply, new_state}
  end

  def handle_cast({:recv, frame}, state) do
    recv(frame, state)
  end

  def handle_cast({:send, type}, state) do
    sendf(type, state)
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  # sendf

  @spec sendf(:goaway | :ping, t) :: {:noreply, t}
  def sendf(:ping, %Connection{socket: socket} = state) do
    bin = Ping.new |> Encodable.to_bin
    :ssl.send(socket, bin)
    {:noreply, state}
  end
  def sendf(:goaway, %Connection{socket: socket,
                                 flow_control: flow} = state) do
    bin = flow.stream_id |> Goaway.new |> Encodable.to_bin
    :ssl.send(socket, bin)
    {:noreply, state}
  end
  def sendf(_else, state) do
    {:noreply, state}
  end

  # recv

  @spec recv(frame, t) :: {:noreply, t}
  def recv(%Frame.RstStream{}, state) do
    Logger.error("recv unstarted stream rst")
    {:noreply, state}
  end

  def recv(%Frame.Ping{ack: true}, %{client: pid} = state) do
    send(pid, {:pong, self()})
    {:noreply, state}
  end
  def recv(%Frame.Ping{ack: false}, %{client: pid} = state) do
    send(pid, {:ping, self()})
    {:noreply, state}
  end

  def recv(%Frame.Settings{ack: true}, state) do
    # Do nothing on ACK. Might change in the future.
    {:noreply, state}
  end
  def recv(%Frame.Settings{ack: false, settings: settings},
           %{flow_control: flow, ref: ref} = state) do

    {:ok, old_settings} = ConnectionSettings.fetch(ref)
    {:ok, settings} = ConnectionSettings.update(ref, settings)
    flow = Connection.FlowControl.put_settings(flow, settings)

    pid = Hpack.via_tuple(ref, :encoder)
    Hpack.update_max_table_size(pid, settings.max_header_list_size)

    old_window = old_settings.initial_window_size
    new_window = settings.initial_window_size
    IO.puts("Initial Window Change: #{old_window} -> #{new_window}")
    window_diff = new_window - old_window

    for stream_id <- flow.active_streams do
      pid = Stream.via_tuple(ref, stream_id)
      Stream.cast_recv(pid, {:window_change, window_diff})
    end

    bin = Frame.Settings.ack |> Encodable.to_bin
    :ssl.send(state.socket, bin)

    {:noreply, %{state | flow_control: flow}}
  end

  def recv(%Goaway{last_stream_id: id,
                   error_code: error,
                   debug_data: debug}, %{client: pid} = state) do
    log_goaway(error, id, debug)
    send pid, {:closed, self()}
    {:noreply, state}
  end

  def recv(%Frame.WindowUpdate{window_size_increment: inc}, state) do
    flow = Connection.FlowControl.increment_window(state.flow_control, inc)
    {:noreply, %{state | flow_control: flow}}
  end

  def recv(_else, state), do: {:noreply, state}

  defp do_send_headers(headers, payload, %{flow_control: flow} = state) do
    flow =
      flow
      |> Connection.FlowControl.add(headers, payload)
      |> Connection.FlowControl.process(state)

    %{state | flow_control: flow}
  end

  def log_goaway(code, id, bin) do
    error = Error.string(code)
    Logger.error "Got GOAWAY, #{error}, Last Stream: #{id}, Rest: #{bin}"
  end

  def handle_info({:finished, response},
                  %{client: pid, flow_control: flow} = state) do

    send(pid, {:end_stream, response})

    flow =
      flow
      |> Connection.FlowControl.decrement_active_stream_count
      |> Connection.FlowControl.remove_active(response.id)
      |> Connection.FlowControl.process(state)

    {:noreply, %{state | flow_control: flow}}
  end

  def handle_info({:push_promise, stream}, %{client: pid} = state) do
    send(pid, {:push_promise, stream})
    {:noreply, state}
  end

  def handle_info({:tcp, _socket, _bin}, state) do
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    maybe_reconnect(state)
  end

  def handle_info({:ssl, _socket, bin}, state) do
    do_recv_ssl(bin, state)
  end

  def handle_info({:ssl_closed, _socket}, state) do
    maybe_reconnect(state)
  end

  defp do_recv_ssl(bin, %{socket: socket} = state) do
    bin = state.buffer <> bin
    case parse_ssl(socket, bin, state) do
      {:error, bin, state} ->
        :ssl.setopts(socket, [{:active, :once}])
        {:noreply, %{state | buffer: bin}}
    end
  end

  def parse_ssl(socket, bin, state) do
    case Kadabra.Frame.new(bin) do
      {:ok, frame, rest} ->
        state = handle_response(frame, state)
        parse_ssl(socket, rest, state)
      {:error, bin} ->
        {:error, bin, state}
    end
  end

  def handle_response(frame, _state) when is_binary(frame) do
    Logger.info "Got binary: #{inspect(frame)}"
  end
  def handle_response(frame, state) do
    parsed_frame =
      case frame.type do
        @data -> Frame.Data.new(frame)
        @headers -> Frame.Headers.new(frame)
        @rst_stream -> Frame.RstStream.new(frame)
        @settings ->
          case Frame.Settings.new(frame) do
            {:ok, settings_frame} -> settings_frame
            _else -> :error
          end
        @push_promise -> Frame.PushPromise.new(frame)
        @ping -> Frame.Ping.new(frame)
        @goaway -> Frame.Goaway.new(frame)
        @window_update -> Frame.WindowUpdate.new(frame)
        @continuation -> Frame.Continuation.new(frame)
        _ ->
          Logger.info("Unknown frame: #{inspect(frame)}")
          :error
      end

    process(parsed_frame, state)
  end

  @spec process(frame, t) :: :ok
  def process(%Frame.Data{stream_id: 0}, state) do
    # TODO: This is an error
    state
  end
  def process(%Frame.Data{stream_id: stream_id} = frame, state) do
    pid = Stream.via_tuple(state.ref, stream_id)
    send_window_update(state.socket, frame)
    Stream.cast_recv(pid, frame)
    state
  end

  def process(%Frame.Headers{} = frame, state) do
    pid = Stream.via_tuple(state.ref, frame.stream_id)
    Stream.cast_recv(pid, frame)
    state
  end

  def process(%Frame.RstStream{} = frame, state) do
    pid = Stream.via_tuple(state.ref, frame.stream_id)
    Stream.cast_recv(pid, frame)
    state
  end

  def process(%Frame.Settings{} = frame, state) do
    # Process immediately
    recv(frame, state)
    state
  end

  def process(%Frame.PushPromise{stream_id: stream_id} = frame, state) do
    {:ok, settings} = Kadabra.ConnectionSettings.fetch(state.ref)
    {:ok, pid} = Kadabra.Supervisor.start_stream(state, settings, stream_id)

    flow = Connection.FlowControl.add_active(state.flow_control, stream_id)

    Stream.cast_recv(pid, frame)
    %{state | flow_control: flow}
  end

  def process(%Frame.Ping{} = frame, state) do
    # Process immediately
    recv(frame, state)
    state
  end

  def process(%Frame.Goaway{} = frame, state) do
    GenServer.cast(self(), {:recv, frame})
    state
  end

  def process(%Frame.WindowUpdate{stream_id: 0} = frame, state) do
    Stream.cast_recv(self(), frame)
    state
  end
  def process(%Frame.WindowUpdate{stream_id: stream_id} = frame, state) do
    pid = Stream.via_tuple(state.ref, stream_id)
    Stream.cast_recv(pid, frame)
    state
  end

  def process(%Frame.Continuation{stream_id: stream_id} = frame, state) do
    pid = Stream.via_tuple(state.ref, stream_id)
    Stream.cast_recv(pid, frame)
    state
  end

  def process(:error, state), do: state

  def send_window_update(_socket, %Data{data: nil}), do: :ok
  def send_window_update(socket, %Data{stream_id: sid,
                                       data: data}) when byte_size(data) > 0 do
    bin = data |> WindowUpdate.new |> Encodable.to_bin
    :ssl.send(socket, bin)

    s_bin =
      sid
      |> WindowUpdate.new(byte_size(data))
      |> Encodable.to_bin
    :ssl.send(socket, s_bin)
  end
  def send_window_update(_socket, %Data{data: _data}), do: :ok

  def maybe_reconnect(%{reconnect: false, client: pid} = state) do
    Logger.debug "Socket closed, not reopening, informing client"
    send(pid, {:closed, self()})
    {:noreply, reset_state(state, nil)}
  end
  def maybe_reconnect(%{reconnect: true,
                        uri: uri,
                        opts: opts,
                        client: pid} = state) do
    case Connection.Ssl.connect(uri, opts) do
      {:ok, socket} ->
        send_preface_and_settings(socket)
        Logger.debug "Socket closed, reopened automatically"
        {:noreply, reset_state(state, socket)}
      {:error, error} ->
        Logger.error "Socket closed, reopening failed with #{error}"
        send(pid, :closed)
        {:stop, :normal, state}
    end
  end

  defp reset_state(state, socket) do
    %{state | socket: socket}
  end
end
