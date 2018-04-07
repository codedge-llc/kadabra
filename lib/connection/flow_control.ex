defmodule Kadabra.Connection.FlowControl do
  @moduledoc false

  defstruct queue: :queue.new(),
            stream_id: 1,
            active_stream_count: 0,
            active_streams: MapSet.new(),
            streams: %{},
            window: 65_535,
            settings: %Kadabra.Connection.Settings{}

  alias Kadabra.{Connection}

  @type t :: %__MODULE__{
          queue: :queue.queue(),
          stream_id: pos_integer,
          active_stream_count: non_neg_integer,
          active_streams: MapSet.t(),
          window: integer,
          settings: Connection.Settings.t()
        }

  @spec update_settings(t, Connection.Settings.t()) :: t
  def update_settings(flow_control, nil), do: flow_control

  def update_settings(%{settings: old_settings} = flow_control, settings) do
    settings = Connection.Settings.merge(old_settings, settings)
    %{flow_control | settings: settings}
  end

  @doc ~S"""
  Increments current `stream_id`.

  ## Examples

      iex> flow = %Kadabra.Connection.FlowControl{stream_id: 5}
      iex> increment_stream_id(flow)
      %Kadabra.Connection.FlowControl{stream_id: 7}
  """
  @spec increment_stream_id(t) :: t
  def increment_stream_id(flow_control) do
    %{flow_control | stream_id: flow_control.stream_id + 2}
  end

  @doc ~S"""
  Increments open stream count.

  ## Examples

      iex> flow = %Kadabra.Connection.FlowControl{active_stream_count: 2}
      iex> increment_active_stream_count(flow)
      %Kadabra.Connection.FlowControl{active_stream_count: 3}
  """
  @spec increment_active_stream_count(t) :: t
  def increment_active_stream_count(flow_control) do
    %{flow_control | active_stream_count: flow_control.active_stream_count + 1}
  end

  @doc ~S"""
  Decrements open stream count.

  ## Examples

      iex> flow = %Kadabra.Connection.FlowControl{active_stream_count: 2}
      iex> decrement_active_stream_count(flow)
      %Kadabra.Connection.FlowControl{active_stream_count: 1}
  """
  @spec decrement_active_stream_count(t) :: t
  def decrement_active_stream_count(flow_control) do
    %{flow_control | active_stream_count: flow_control.active_stream_count - 1}
  end

  @doc ~S"""
  Increments available window.

  ## Examples

      iex> flow = %Kadabra.Connection.FlowControl{window: 1_000}
      iex> increment_window(flow, 500)
      %Kadabra.Connection.FlowControl{window: 1_500}
  """
  @spec increment_window(t, pos_integer) :: t
  def increment_window(%{window: window} = flow_control, amount) do
    %{flow_control | window: window + amount}
  end

  @doc ~S"""
  Decrements available window.

  ## Examples

      iex> flow = %Kadabra.Connection.FlowControl{window: 1_000}
      iex> decrement_window(flow, 500)
      %Kadabra.Connection.FlowControl{window: 500}
  """
  @spec decrement_window(t, pos_integer) :: t
  def decrement_window(%{window: window} = flow_control, amount) do
    %{flow_control | window: window - amount}
  end

  @doc ~S"""
  Marks stream_id as active.

  ## Examples

      iex> flow = add_active(%Kadabra.Connection.FlowControl{}, 1)
      iex> flow.active_streams
      #MapSet<[1]>
  """
  def add_active(%{active_streams: active} = flow_control, stream_id) do
    %{flow_control | active_streams: MapSet.put(active, stream_id)}
  end

  @doc ~S"""
  Marks stream_id as active.

  ## Examples

      iex> flow = remove_active(%Kadabra.Connection.FlowControl{
      ...> active_streams: MapSet.new([1, 3])}, 1)
      iex> flow.active_streams
      #MapSet<[3]>
  """
  def remove_active(%{active_streams: active} = flow_control, stream_id) do
    %{flow_control | active_streams: MapSet.delete(active, stream_id)}
  end

  @doc ~S"""
  Adds new sendable item to the queue.

  ## Examples

      iex> flow = add(%Kadabra.Connection.FlowControl{}, %Kadabra.Request{})
      iex> :queue.len(flow.queue)
      1
  """
  @spec add(t, Kadabra.Request.t()) :: t
  def add(%{queue: queue} = flow_control, request) do
    queue = :queue.in(request, queue)
    %{flow_control | queue: queue}
  end

  @spec process(t, Connection.t()) :: t
  def process(%{queue: queue} = flow, conn) do
    with {{:value, request}, queue} <- :queue.out(queue),
         {:can_send, true} <- {:can_send, can_send?(flow)} do
      stream = get_stream(flow, flow.stream_id)
      size = byte_size(request.body || <<>>)

      stream = Kadabra.Stream.send_frame(stream, request, conn)

      flow
      |> Map.put(:queue, queue)
      |> put_stream(stream)
      |> decrement_window(size)
      |> add_active(flow.stream_id)
      |> increment_active_stream_count()
      |> increment_stream_id()
    else
      {:empty, _queue} -> flow
      {:can_send, false} -> flow
    end
  end

  @doc ~S"""
  Returns true if active_streams is less than max streams and window
  is positive.

  ## Examples

      iex> settings = %Kadabra.Connection.Settings{max_concurrent_streams: 100}
      iex> flow = %Kadabra.Connection.FlowControl{active_stream_count: 3,
      ...> window: 500, settings: settings}
      iex> can_send?(flow)
      true

      iex> settings = %Kadabra.Connection.Settings{max_concurrent_streams: 100}
      iex> flow = %Kadabra.Connection.FlowControl{active_stream_count: 3,
      ...> window: 0, settings: settings}
      iex> can_send?(flow)
      false

      iex> settings = %Kadabra.Connection.Settings{max_concurrent_streams: 1}
      iex> flow = %Kadabra.Connection.FlowControl{active_stream_count: 3,
      ...> window: 500, settings: settings}
      iex> can_send?(flow)
      false
  """
  @spec can_send?(t) :: boolean
  def can_send?(%{active_stream_count: count, settings: s, window: bytes}) do
    count < s.max_concurrent_streams and bytes > 0
  end

  def get_stream(flow, stream_id) do
    Map.get(
      flow.streams,
      stream_id,
      Kadabra.Stream.new(flow.settings, stream_id)
    )
  end

  def put_stream(flow, stream) do
    streams = Map.put(flow.streams, stream.id, stream)
    %{flow | streams: streams}
  end

  def delete_stream(flow, stream_id) do
    streams = Map.delete(flow.streams, stream_id)
    %{flow | streams: streams}
  end
end
