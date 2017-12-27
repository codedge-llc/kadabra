defmodule Kadabra.Connection do
  @moduledoc false

  defstruct ref: nil,
            buffer: "",
            client: nil,
            uri: nil,
            scheme: :https,
            opts: [],
            socket: nil,
            queue: nil,
            flow_control: nil

  use GenStage
  require Logger

  alias Kadabra.{
    Connection,
    ConnectionQueue,
    Encodable,
    Error,
    Frame,
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
          ref: nil,
          scheme: :https,
          socket: sock,
          uri: charlist | String.t()
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
    socket = Socket.via_tuple(sup)
    state = initial_state(socket, uri, pid, ref, opts)
    {:consumer, state, subscribe_to: [ConnectionQueue.via_tuple(sup)]}
  end

  defp initial_state(socket, uri, pid, ref, opts) do
    settings = Keyword.get(opts, :settings, Connection.Settings.default())

    %__MODULE__{
      ref: ref,
      client: pid,
      uri: uri,
      scheme: Keyword.get(opts, :scheme, :https),
      opts: opts,
      socket: socket,
      flow_control: %Connection.FlowControl{
        settings: settings
      }
    }
  end

  defp send_preface_and_settings(socket, settings) do
    Socket.sendf(socket, Http2.connection_preface())

    bin =
      %Frame.Settings{settings: settings || Connection.Settings.default()}
      |> Encodable.to_bin()

    Socket.sendf(socket, bin)
  end

  def handle_call({:recv, frame}, from, state) do
    GenStage.reply(from, :ok)
    recv(frame, state)
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
    send_preface_and_settings(state.socket, state.flow_control.settings)
    {:manual, %{state | queue: from}}
  end

  # sendf

  @spec sendf(:goaway | :ping, t) :: {:noreply, [], t}
  def sendf(:ping, %Connection{socket: socket} = state) do
    bin = Ping.new() |> Encodable.to_bin()
    Socket.sendf(socket, bin)
    {:noreply, [], state}
  end

  def sendf(:goaway, state) do
    %Connection{socket: socket, client: pid, flow_control: flow} = state
    bin = flow.stream_id |> Goaway.new() |> Encodable.to_bin()
    Socket.sendf(socket, bin)

    close(state)
    send(pid, {:closed, self()})

    {:stop, :normal, state}
  end

  def sendf(_else, state) do
    {:noreply, [], state}
  end

  def close(state) do
    Hpack.close(state.ref)

    for stream <- state.flow_control.active_streams do
      Stream.close(state.ref, stream)
    end
  end

  # recv

  def recv(%Data{stream_id: 0}, state) do
    # This is an error
    {:noreply, [], state}
  end

  def recv(%Data{stream_id: stream_id} = frame, state) do
    send_window_update(state.socket, frame)

    state.ref
    |> Stream.via_tuple(stream_id)
    |> Stream.cast_recv(frame)

    {:noreply, [], state}
  end

  def recv(%Headers{stream_id: stream_id} = frame, state) do
    state.ref
    |> Stream.via_tuple(stream_id)
    |> Stream.cast_recv(frame)

    {:noreply, [], state}
  end

  @spec recv(frame, t) :: {:noreply, [], t}
  def recv(%RstStream{} = frame, state) do
    state.ref
    |> Stream.via_tuple(frame.stream_id)
    |> Stream.cast_recv(frame)

    {:noreply, [], state}
  end

  def recv(%PushPromise{stream_id: stream_id} = frame, state) do
    {:ok, pid} = StreamSupervisor.start_stream(state, stream_id)

    flow = Connection.FlowControl.add_active(state.flow_control, stream_id)

    Stream.cast_recv(pid, frame)
    {:noreply, [], %{state | flow_control: flow}}
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
    Socket.sendf(state.socket, bin)

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
    Socket.sendf(state.socket, bin)

    to_ask = settings.max_concurrent_streams - flow.active_stream_count
    GenStage.ask(state.queue, to_ask)

    {:noreply, [], %{state | flow_control: flow}}
  end

  def recv(%Frame.Settings{ack: true}, state) do
    # Do nothing on ACK. Might change in the future.
    {:noreply, [], state}
  end

  def recv(%Goaway{} = goaway, %{client: pid} = state) do
    log_goaway(goaway)
    close(state)
    send(pid, {:closed, self()})

    {:stop, :normal, state}
  end

  def recv(%WindowUpdate{stream_id: 0, window_size_increment: inc}, state) do
    flow = Connection.FlowControl.increment_window(state.flow_control, inc)
    {:noreply, [], %{state | flow_control: flow}}
  end

  def recv(%WindowUpdate{stream_id: stream_id} = frame, state) do
    pid = Stream.via_tuple(state.ref, stream_id)
    Stream.cast_recv(pid, frame)
    {:noreply, [], state}
  end

  def recv(%Continuation{stream_id: stream_id} = frame, state) do
    pid = Stream.via_tuple(state.ref, stream_id)
    Stream.cast_recv(pid, frame)
    {:noreply, [], state}
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
    flow =
      requests
      |> Enum.reduce(state.flow_control, &Connection.FlowControl.add(&2, &1))
      |> Connection.FlowControl.process(state)

    %{state | flow_control: flow}
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

  def handle_info({:closed, _pid}, state) do
    Logger.debug("Socket closed, informing client")
    send(state.client, {:closed, self()})
    close(state)
    {:noreply, %{state | socket: nil}}
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

  def send_window_update(_socket, %Data{data: nil}), do: :ok

  def send_window_update(_socket, %Data{data: ""}), do: :ok

  def send_window_update(socket, %Data{stream_id: sid, data: data}) do
    bin = data |> WindowUpdate.new() |> Encodable.to_bin()
    Socket.sendf(socket, bin)

    s_bin =
      sid
      |> WindowUpdate.new(byte_size(data))
      |> Encodable.to_bin()

    Socket.sendf(socket, s_bin)
  end
end
