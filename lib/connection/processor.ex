defmodule Kadabra.Connection.Processor do
  @moduledoc false

  require Logger

  alias Kadabra.{
    Connection,
    Error,
    Frame,
    Hpack,
    Stream,
    StreamSet
  }

  alias Kadabra.Connection.{Egress, FlowControl}

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

  @spec process(frame, Connection.t()) ::
          {:ok, Connection.t()}
          | {:connection_error, atom, binary, Connection.t()}
  def process(bin, state) when is_binary(bin) do
    Logger.info("Got binary: #{inspect(bin)}")
    state
  end

  def process(%Data{stream_id: 0}, state) do
    reason = "Recv DATA with stream ID of 0"
    {:connection_error, :PROTOCOL_ERROR, reason, state}
  end

  def process(%Data{stream_id: stream_id} = frame, %{config: config} = state) do
    available = FlowControl.window_max() - state.remote_window
    bin_size = byte_size(frame.data)
    size = min(available, bin_size)

    Egress.send_window_update(config.socket, 0, size)
    Egress.send_window_update(config.socket, stream_id, bin_size)

    pid = StreamSet.pid_for(state.flow_control.stream_set, stream_id)
    Stream.call_recv(pid, frame)

    {:ok, %{state | remote_window: state.remote_window + size}}
  end

  def process(%Headers{stream_id: stream_id} = frame, state) do
    pid = StreamSet.pid_for(state.flow_control.stream_set, stream_id)

    case Stream.call_recv(pid, frame) do
      :ok ->
        {:ok, state}

      {:connection_error, error} ->
        {:connection_error, error, nil, state}
    end
  end

  def process(%RstStream{stream_id: 0}, state) do
    Logger.error("recv unstarted stream rst")
    {:ok, state}
  end

  def process(%RstStream{stream_id: stream_id} = frame, state) do
    pid = StreamSet.pid_for(state.flow_control.stream_set, stream_id)
    Stream.call_recv(pid, frame)

    {:ok, state}
  end

  # nil settings means use default
  def process(%Frame.Settings{ack: false, settings: nil}, state) do
    %{flow_control: flow, config: config} = state

    Egress.send_settings_ack(config.socket)

    state = request_more_streams(flow.stream_set.max_concurrent_streams, state)

    {:ok, state}
  end

  def process(%Frame.Settings{ack: false, settings: settings}, state) do
    %{flow_control: flow, config: config} = state
    old_settings = state.remote_settings
    settings = Connection.Settings.merge(old_settings, settings)

    flow =
      FlowControl.update_settings(
        flow,
        settings.initial_window_size,
        settings.max_frame_size,
        settings.max_concurrent_streams
      )

    notify_settings_change(old_settings, settings, flow)

    Hpack.update_max_table_size(
      state.config.decoder,
      settings.max_header_list_size
    )

    Egress.send_settings_ack(config.socket)

    state = request_more_streams(settings.max_concurrent_streams, state)

    {:ok, %{state | flow_control: flow, remote_settings: settings}}
  end

  def process(%Frame.Settings{ack: true}, %{config: c} = state) do
    Hpack.update_max_table_size(
      c.encoder,
      state.local_settings.max_header_list_size
    )

    Hpack.update_max_table_size(
      c.decoder,
      state.local_settings.max_header_list_size
    )

    available = FlowControl.window_max() - state.remote_window
    Egress.send_window_update(c.socket, 0, available)

    {:ok, %{state | remote_window: FlowControl.window_max()}}
  end

  def process(%PushPromise{stream_id: stream_id} = frame, state) do
    %{config: config, flow_control: flow_control} = state

    %{
      initial_window_size: window,
      max_frame_size: max_frame
    } = flow_control

    stream = Stream.new(config, stream_id, window, max_frame)

    case Stream.start_link(stream) do
      {:ok, pid} ->
        Stream.call_recv(pid, frame)
        state = add_active(state, stream_id, pid)
        {:ok, state}

      error ->
        raise "#{inspect(error)}"
    end
  end

  def process(%Ping{stream_id: sid}, state) when sid != 0 do
    reason = "Recv PING with stream ID of #{sid}"
    {:connection_error, :PROTOCOL_ERROR, reason, state}
  end

  def process(%Ping{data: data}, state) when byte_size(data) != 8 do
    reason = "Recv PING with payload of #{byte_size(data)} bytes"
    {:connection_error, :FRAME_SIZE_ERROR, reason, state}
  end

  def process(%Ping{ack: false}, %{config: config} = state) do
    Kernel.send(config.client, {:ping, self()})
    {:ok, state}
  end

  def process(%Ping{ack: true}, %{config: config} = state) do
    Kernel.send(config.client, {:pong, self()})
    {:ok, state}
  end

  def process(%Goaway{} = frame, state) do
    log_goaway(frame)
    {:connection_error, :NO_ERROR, nil, state}
  end

  def process(%WindowUpdate{stream_id: 0, window_size_increment: inc}, state)
      when inc <= 0 do
    reason = "Recv WINDOW_UPDATE with increment of #{inc}"
    {:connection_error, :PROTOCOL_ERROR, reason, state}
  end

  def process(%WindowUpdate{stream_id: 0, window_size_increment: inc}, state) do
    flow = FlowControl.increment_window(state.flow_control, inc)
    {:ok, %{state | flow_control: flow}}
  end

  def process(%WindowUpdate{stream_id: stream_id} = frame, state) do
    pid = StreamSet.pid_for(state.flow_control.stream_set, stream_id)
    Stream.call_recv(pid, frame)

    {:ok, state}
  end

  def process(%Continuation{stream_id: stream_id} = frame, state) do
    pid = StreamSet.pid_for(state.flow_control.stream_set, stream_id)
    Stream.call_recv(pid, frame)

    {:ok, state}
  end

  def process(frame, state) do
    if debug_log?() do
      """
      Unknown RECV on connection
      Frame: #{inspect(frame)}
      State: #{inspect(state)}
      """
      |> Logger.info()
    end

    {:ok, state}
  end

  defp request_more_streams(:infinite, state) do
    # Any more than this and you exhaust usable stream identifiers
    request_more_streams(1_073_741_823, state)
  end

  defp request_more_streams(max_count, state) do
    to_ask = max_count - state.requested_streams
    GenServer.cast(state.queue, {:ask, to_ask})

    %{state | requested_streams: state.requested_streams + to_ask}
  end

  def add_active(state, stream_id, pid) do
    flow = FlowControl.add_active(state.flow_control, stream_id, pid)
    %{state | flow_control: flow}
  end

  def log_goaway(%Goaway{last_stream_id: id, error_code: c, debug_data: b}) do
    if debug_log?() do
      error = Error.parse(c)
      Logger.error("Got GOAWAY, #{error}, Last Stream: #{id}, Rest: #{b}")
    end
  end

  def notify_settings_change(old_settings, new_settings, %{stream_set: set}) do
    old_settings = old_settings || Connection.Settings.default()
    %{initial_window_size: old_window} = old_settings

    max_frame_size = new_settings.max_frame_size
    new_window = new_settings.initial_window_size
    window_diff = new_window - old_window

    for {_stream_id, pid} <- set.active_streams do
      send(pid, {:settings_change, window_diff, max_frame_size})
    end
  end

  defp debug_log?, do: Application.get_env(:kadabra, :debug_log?)
end
