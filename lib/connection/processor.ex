defmodule Kadabra.Connection.Processor do
  @moduledoc false

  require Logger

  alias Kadabra.{
    Connection,
    Encodable,
    Frame,
    Hpack,
    Socket,
    Stream,
    StreamSupervisor
  }

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

  @spec process(frame, Connection.t()) :: :ok
  def process(bin, state) when is_binary(bin) do
    Logger.info("Got binary: #{inspect(bin)}")
    state
  end

  def process(%Data{stream_id: 0}, state) do
    # This is an error
    {:ok, state}
  end

  def process(%Data{stream_id: stream_id} = frame, %{config: config} = state) do
    send_window_update(config.socket, frame)

    config.ref
    |> Stream.via_tuple(stream_id)
    |> Stream.call_recv(frame)

    {:ok, state}
  end

  def process(%Headers{stream_id: stream_id} = frame, %{config: config} = state) do
    config.ref
    |> Stream.via_tuple(stream_id)
    |> Stream.call_recv(frame)
    |> case do
      :ok ->
        {:ok, state}

      {:connection_error, error} ->
        {:connection_error, error, state}
    end
  end

  def process(%RstStream{stream_id: 0}, state) do
    Logger.error("recv unstarted stream rst")
    {:ok, state}
  end

  def process(%RstStream{} = frame, %{config: config} = state) do
    pid = Stream.via_tuple(config.ref, frame.stream_id)
    Stream.call_recv(pid, frame)
    {:ok, state}
  end

  # nil settings means use default
  def process(%Frame.Settings{ack: false, settings: nil}, state) do
    %{flow_control: flow, config: config} = state

    bin = Frame.Settings.ack() |> Encodable.to_bin()
    Socket.send(config.socket, bin)

    case flow.settings.max_concurrent_streams do
      :infinite ->
        GenStage.ask(state.queue, 2_000_000_000)

      max ->
        to_ask = max - flow.active_stream_count
        GenStage.ask(state.queue, to_ask)
    end

    {:ok, state}
  end

  def process(%Frame.Settings{ack: false, settings: settings}, state) do
    %{flow_control: flow, config: config} = state
    old_settings = flow.settings
    flow = Connection.FlowControl.update_settings(flow, settings)

    notify_settings_change(config.ref, old_settings, flow)

    config.ref
    |> Hpack.via_tuple(:encoder)
    |> Hpack.update_max_table_size(settings.max_header_list_size)

    bin = Frame.Settings.ack() |> Encodable.to_bin()
    Socket.send(config.socket, bin)

    to_ask = settings.max_concurrent_streams - flow.active_stream_count
    GenStage.ask(state.queue, to_ask)

    {:ok, %{state | flow_control: flow}}
  end

  def process(%Frame.Settings{ack: true}, state) do
    send_huge_window_update(state.config.socket, state.flow_control)
    {:ok, state}
  end

  def process(%PushPromise{stream_id: stream_id} = frame, state) do
    %{config: config, flow_control: flow_control} = state
    {:ok, pid} = StreamSupervisor.start_stream(config, flow_control, stream_id)

    Stream.call_recv(pid, frame)

    flow = Connection.FlowControl.add_active(flow_control, stream_id)

    {:ok, %{state | flow_control: flow}}
  end

  def process(%Frame.Ping{stream_id: sid}, state) when sid != 0 do
    {:connection_error, "PROTOCOL_ERROR", state}
  end

  def process(%Frame.Ping{data: data}, state) when byte_size(data) != 8 do
    {:connection_error, "FRAME_SIZE_ERROR", state}
  end

  def process(%Frame.Ping{ack: false}, %{config: config} = state) do
    Kernel.send(config.client, {:ping, self()})
    {:ok, state}
  end

  def process(%Frame.Ping{ack: true}, %{config: config} = state) do
    Kernel.send(config.client, {:pong, self()})
    {:ok, state}
  end

  def process(%Goaway{} = frame, state) do
    GenStage.cast(self(), {:recv, frame})
    {:ok, state}
  end

  def process(%WindowUpdate{stream_id: 0, window_size_increment: inc}, state) do
    flow = Connection.FlowControl.increment_window(state.flow_control, inc)
    {:ok, %{state | flow_control: flow}}
  end

  def process(%WindowUpdate{stream_id: stream_id} = frame, state) do
    pid = Stream.via_tuple(state.config.ref, stream_id)
    Stream.cast_recv(pid, frame)
    {:ok, state}
  end

  def process(%Continuation{stream_id: stream_id} = frame, state) do
    pid = Stream.via_tuple(state.config.ref, stream_id)
    Stream.call_recv(pid, frame)
    {:ok, state}
  end

  def process(frame, state) do
    """
    Unknown RECV on connection
    Frame: #{inspect(frame)}
    State: #{inspect(state)}
    """
    |> Logger.info()

    {:ok, state}
  end

  @spec send_window_update(pid, Data.t()) :: no_return
  def send_window_update(_socket, %Data{data: nil}), do: :ok

  def send_window_update(_socket, %Data{data: ""}), do: :ok

  def send_window_update(socket, %Data{stream_id: sid, data: data}) do
    size = byte_size(data)
    send_window_update(socket, 0, size)
    send_window_update(socket, sid, size)
  end

  @spec send_window_update(pid, non_neg_integer, integer) :: no_return
  def send_window_update(socket, stream_id, bytes)
      when bytes > 0 and bytes < 2_147_483_647 do
    bin =
      stream_id
      |> WindowUpdate.new(bytes)
      |> Encodable.to_bin()

    Socket.send(socket, bin)
  end

  def send_window_update(_socket, _stream_id, _bytes), do: :ok

  def send_huge_window_update(socket, flow_control) do
    available =
      Connection.FlowControl.window_max() -
        Connection.FlowControl.window_default()

    send_window_update(socket, 0, available)
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
end
