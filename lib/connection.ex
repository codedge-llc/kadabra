defmodule Kadabra.Connection do
  @moduledoc false

  defstruct buffer: "",
            client: nil,
            flow_control: nil,
            opts: [],
            ref: nil,
            socket: nil,
            supervisor: nil,
            uri: nil,
            queue: nil

  use GenStage
  require Logger

  alias Kadabra.{
    Connection,
    ConnectionQueue,
    Encodable,
    Error,
    Frame,
    FrameParser,
    Hpack,
    Http2,
    Stream,
    StreamSupervisor
  }

  alias Kadabra.Connection.Socket

  alias Kadabra.Frame.{
    Continuation,
    Data,
    Goaway,
    Headers,
    Ping,
    PushPromise,
    RstStream,
    WindowUpdate
  }

  @type t :: %__MODULE__{
          buffer: binary,
          client: pid,
          flow_control: term,
          opts: Keyword.t(),
          ref: reference,
          socket: sock,
          uri: URI.t()
        }

  @type sock :: {:sslsocket, any, pid | {any, any}}

  @type frame ::
          Data.t()
          | Headers.t()
          | RstStream.t()
          | Frame.Settings.t()
          | PushPromise.t()
          | Ping.t()
          | Goaway.t()
          | WindowUpdate.t()
          | Continuation.t()

  def start_link(uri, pid, sup, ref, opts \\ []) do
    name = via_tuple(sup)
    start_opts = {:ok, uri, pid, sup, ref, opts}
    GenStage.start_link(__MODULE__, start_opts, name: name)
  end

  def via_tuple(ref) do
    {:via, Registry, {Registry.Kadabra, {ref, __MODULE__}}}
  end

  def init({:ok, uri, pid, sup, ref, opts}) do
    case Socket.connect(uri, opts) do
      {:ok, socket} ->
        send_preface_and_settings(socket, opts[:settings])
        state = initial_state(socket, uri, pid, sup, ref, opts)
        {:consumer, state, subscribe_to: [ConnectionQueue.via_tuple(sup)]}

      {:error, error} ->
        {:stop, error}
    end
  end

  defp initial_state(socket, uri, pid, sup, ref, opts) do
    settings = Keyword.get(opts, :settings, Connection.Settings.default())

    %__MODULE__{
      ref: ref,
      client: pid,
      uri: uri,
      opts: opts,
      socket: socket,
      supervisor: sup,
      flow_control: %Connection.FlowControl{
        settings: settings
      }
    }
  end

  def close(pid) do
    GenStage.call(pid, :close)
  end

  defp send_preface_and_settings(socket, settings) do
    Socket.send(socket, Http2.connection_preface())

    bin =
      %Frame.Settings{settings: settings || Connection.Settings.default()}
      |> Encodable.to_bin()

    Socket.send(socket, bin)
  end

  def ping(pid) do
    GenStage.cast(pid, {:send, :ping})
  end

  # handle_cast

  def handle_cast({:recv, frame}, state) do
    recv(frame, state)
  end

  def handle_cast({:send, type}, state) do
    sendf(type, state)
  end

  def handle_cast(_msg, state) do
    {:noreply, [], state}
  end

  def handle_events(events, _from, state) do
    state = do_send_headers(events, state)
    {:noreply, [], state}
  end

  def handle_subscribe(:producer, _opts, from, state) do
    {:manual, %{state | queue: from}}
  end

  # handle_call

  def handle_call(:close, _from, %Connection{} = state) do
    %Connection{
      client: pid,
      flow_control: flow,
      socket: socket,
      supervisor: sup
    } = state

    bin = flow.stream_id |> Goaway.new() |> Encodable.to_bin()
    :ssl.send(socket, bin)

    send(pid, {:closed, sup})

    Task.Supervisor.start_child(Kadabra.Tasks, fn ->
      Kadabra.Supervisor.stop(state.supervisor)
    end)

    {:stop, :normal, :ok, state}
  end

  # sendf

  @spec sendf(:goaway | :ping, t) :: {:noreply, [], t}
  def sendf(:ping, %Connection{socket: socket} = state) do
    bin = Ping.new() |> Encodable.to_bin()
    Socket.send(socket, bin)
    {:noreply, [], state}
  end

  def sendf(_else, state) do
    {:noreply, [], state}
  end

  # recv

  @spec recv(frame, t) :: {:noreply, [], t}
  def recv(%Frame.RstStream{}, state) do
    Logger.error("recv unstarted stream rst")
    {:noreply, [], state}
  end

  def recv(%Frame.Ping{ack: true}, %{client: pid} = state) do
    send(pid, {:pong, self()})
    {:noreply, [], state}
  end

  def recv(%Frame.Ping{ack: false}, %{client: pid} = state) do
    send(pid, {:ping, self()})
    {:noreply, [], state}
  end

  # nil settings means use default
  def recv(%Frame.Settings{ack: false, settings: nil}, state) do
    %{flow_control: flow} = state

    bin = Frame.Settings.ack() |> Encodable.to_bin()
    Socket.send(state.socket, bin)

    case flow.settings.max_concurrent_streams do
      :infinite ->
        GenStage.ask(state.queue, 2_000_000_000)

      max ->
        to_ask = max - flow.active_stream_count
        GenStage.ask(state.queue, to_ask)
    end

    {:noreply, [], state}
  end

  def recv(%Frame.Settings{ack: false, settings: settings}, state) do
    %{flow_control: flow, ref: ref} = state
    old_settings = flow.settings
    flow = Connection.FlowControl.update_settings(flow, settings)

    notify_settings_change(ref, old_settings, flow)

    pid = Hpack.via_tuple(ref, :encoder)
    Hpack.update_max_table_size(pid, settings.max_header_list_size)

    bin = Frame.Settings.ack() |> Encodable.to_bin()
    Socket.send(state.socket, bin)

    to_ask = settings.max_concurrent_streams - flow.active_stream_count
    GenStage.ask(state.queue, to_ask)

    {:noreply, [], %{state | flow_control: flow}}
  end

  def recv(%Frame.Settings{ack: true}, state) do
    send_huge_window_update(state.socket)
    {:noreply, [], state}
  end

  def recv(%Goaway{} = frame, %{client: pid} = state) do
    log_goaway(frame)
    send(pid, {:closed, state.supervisor})
    Task.start(fn -> Kadabra.Supervisor.stop(state.supervisor) end)

    {:stop, :normal, state}
  end

  def recv(%WindowUpdate{window_size_increment: inc}, state) do
    flow = Connection.FlowControl.increment_window(state.flow_control, inc)
    {:noreply, [], %{state | flow_control: flow}}
  end

  def recv(frame, state) do
    """
    Unknown RECV on connection
    Frame: #{inspect(frame)}
    State: #{inspect(state)}
    """
    |> Logger.info()

    {:noreply, [], state}
  end

  def notify_settings_change(ref, old_settings, flow) do
    %{initial_window_size: old_window} = old_settings
    %{settings: settings} = flow

    max_frame_size = settings.max_frame_size
    new_window = settings.initial_window_size
    window_diff = new_window - old_window

    for stream_id <- flow.active_streams do
      pid = Stream.via_tuple(ref, stream_id)
      Stream.cast_recv(pid, {:settings_change, window_diff, max_frame_size})
    end
  end

  defp do_send_headers(requests, state) when is_list(requests) do
    Enum.reduce(requests, state, &do_send_headers/2)
  end

  defp do_send_headers(request, %{flow_control: flow} = state) do
    flow =
      flow
      |> Connection.FlowControl.add(request)
      |> Connection.FlowControl.process(state)

    %{state | flow_control: flow}
  end

  def log_goaway(%Goaway{last_stream_id: id, error_code: c, debug_data: b}) do
    error = Error.string(c)
    Logger.error("Got GOAWAY, #{error}, Last Stream: #{id}, Rest: #{b}")
  end

  def handle_info({:finished, response}, state) do
    %{client: pid, flow_control: flow} = state
    send(pid, {:end_stream, response})

    flow =
      flow
      |> Connection.FlowControl.decrement_active_stream_count()
      |> Connection.FlowControl.remove_active(response.id)
      |> Connection.FlowControl.process(state)

    GenStage.ask(state.queue, 1)

    {:noreply, [], %{state | flow_control: flow}}
  end

  def handle_info({:push_promise, stream}, %{client: pid} = state) do
    send(pid, {:push_promise, stream})
    {:noreply, [], state}
  end

  def handle_info({:tcp, _socket, bin}, state) do
    do_recv_bin(bin, state)
    {:noreply, [], state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    handle_disconnect(state)
  end

  def handle_info({:ssl, _socket, bin}, state) do
    do_recv_bin(bin, state)
  end

  def handle_info({:ssl_closed, _socket}, state) do
    handle_disconnect(state)
  end

  defp do_recv_bin(bin, %{socket: socket} = state) do
    bin = state.buffer <> bin

    case parse_bin(socket, bin, state) do
      {:unfinished, bin, state} ->
        Socket.setopts(socket, [{:active, :once}])
        {:noreply, [], %{state | buffer: bin}}
    end
  end

  def parse_bin(socket, bin, state) do
    case FrameParser.parse(bin) do
      {:ok, frame, rest} ->
        state = process(frame, state)
        parse_bin(socket, rest, state)

      {:error, bin} ->
        {:unfinished, bin, state}
    end
  end

  @spec process(frame, t) :: :ok
  def process(bin, state) when is_binary(bin) do
    Logger.info("Got binary: #{inspect(bin)}")
    state
  end

  def process(%Data{stream_id: 0}, state) do
    # This is an error
    state
  end

  def process(%Data{stream_id: stream_id} = frame, state) do
    send_window_update(state.socket, frame)

    state.ref
    |> Stream.via_tuple(stream_id)
    |> Stream.cast_recv(frame)

    state
  end

  def process(%Headers{stream_id: stream_id} = frame, state) do
    state.ref
    |> Stream.via_tuple(stream_id)
    |> Stream.call_recv(frame)

    state
  end

  def process(%RstStream{} = frame, state) do
    pid = Stream.via_tuple(state.ref, frame.stream_id)
    Stream.cast_recv(pid, frame)
    state
  end

  def process(%Frame.Settings{} = frame, state) do
    # Process immediately
    {:noreply, [], state} = recv(frame, state)
    state
  end

  def process(%PushPromise{stream_id: stream_id} = frame, state) do
    {:ok, pid} = StreamSupervisor.start_stream(state, stream_id)
    Stream.call_recv(pid, frame)

    flow = Connection.FlowControl.add_active(state.flow_control, stream_id)

    %{state | flow_control: flow}
  end

  def process(%Ping{} = frame, state) do
    # Process immediately
    recv(frame, state)
    state
  end

  def process(%Goaway{} = frame, state) do
    GenStage.cast(self(), {:recv, frame})
    state
  end

  def process(%WindowUpdate{stream_id: 0} = frame, state) do
    Stream.cast_recv(self(), frame)
    state
  end

  def process(%WindowUpdate{stream_id: stream_id} = frame, state) do
    pid = Stream.via_tuple(state.ref, stream_id)
    Stream.cast_recv(pid, frame)
    state
  end

  def process(%Continuation{stream_id: stream_id} = frame, state) do
    pid = Stream.via_tuple(state.ref, stream_id)
    Stream.call_recv(pid, frame)
    state
  end

  def process(_error, state), do: state

  def send_window_update(_socket, %Data{data: nil}), do: :ok

  def send_window_update(_socket, %Data{data: ""}), do: :ok

  def send_window_update(socket, %Data{stream_id: sid, data: data}) do
    bin = data |> WindowUpdate.new() |> Encodable.to_bin()
    Socket.send(socket, bin)

    s_bin =
      sid
      |> WindowUpdate.new(byte_size(data))
      |> Encodable.to_bin()

    Socket.send(socket, s_bin)
  end

  def send_huge_window_update(socket) do
    bin =
      0
      |> Frame.WindowUpdate.new(2_000_000_000)
      |> Encodable.to_bin()

    Socket.send(socket, bin)
  end

  def handle_disconnect(state) do
    Logger.debug("Socket closed, informing client")
    send(state.client, {:closed, state.supervisor})
    Task.start(fn -> Kadabra.Supervisor.stop(state.supervisor) end)

    {:stop, :normal, state}
  end
end
