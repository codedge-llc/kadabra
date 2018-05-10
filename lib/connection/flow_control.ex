defmodule Kadabra.Connection.FlowControl do
  @moduledoc false

  @default_window_size round(:math.pow(2, 16) - 1)
  @max_window_size round(:math.pow(2, 31) - 1)

  @default_initial_window_size round(:math.pow(2, 16) - 1)
  @default_max_frame_size round(:math.pow(2, 14))

  defstruct queue: :queue.new(),
            stream_id: 1,
            active_stream_count: 0,
            active_streams: %{},
            initial_window_size: @default_initial_window_size,
            max_frame_size: @default_max_frame_size,
            max_concurrent_streams: :infinite,
            window: @default_window_size

  alias Kadabra.{Config, Stream}

  @type t :: %__MODULE__{
          queue: :queue.queue(),
          stream_id: pos_integer,
          active_stream_count: non_neg_integer,
          active_streams: %{},
          initial_window_size: non_neg_integer,
          max_frame_size: non_neg_integer,
          max_concurrent_streams: non_neg_integer | :infinite,
          window: integer
        }

  def window_default, do: @default_window_size

  def window_max, do: @max_window_size

  @spec update_settings(t(), integer, integer, integer) :: t()
  def update_settings(flow_control, initial_window, max_frame, max_streams) do
    flow_control
    |> Map.put(:initial_window_size, initial_window)
    |> Map.put(:max_frame_size, max_frame)
    |> Map.put(:max_concurrent_streams, max_streams)
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

      iex> flow = add_active(%Kadabra.Connection.FlowControl{}, 1, :pid)
      iex> flow.active_streams
      %{1 => :pid}
  """
  def add_active(%{active_streams: active} = flow_control, stream_id, pid) do
    %{flow_control | active_streams: Map.put(active, stream_id, pid)}
  end

  @doc ~S"""
  Removes stream_id from active set.

  ## Examples

      iex> flow = remove_active(%Kadabra.Connection.FlowControl{
      ...> active_streams: %{1 => :test, 3 => :pid}}, 1)
      iex> flow.active_streams
      %{3 => :pid}
  """
  def remove_active(%{active_streams: active} = flow_control, pid)
      when is_pid(pid) do
    updated =
      active
      |> Enum.filter(fn {_, p} -> p != pid end)
      |> Enum.into(%{})

    %{flow_control | active_streams: updated}
  end

  def remove_active(%{active_streams: active} = flow_control, stream_id)
      when is_integer(stream_id) do
    %{flow_control | active_streams: Map.delete(active, stream_id)}
  end

  @doc ~S"""
  Adds new sendable item to the queue.

  ## Examples

      iex> flow = add(%Kadabra.Connection.FlowControl{}, %Kadabra.Request{})
      iex> :queue.len(flow.queue)
      1
  """
  @spec add(t, Kadabra.Request.t()) :: t
  def add(%{queue: queue} = flow_control, requests) when is_list(requests) do
    queue = Enum.reduce(requests, queue, &:queue.in(&1, &2))
    %{flow_control | queue: queue}
  end

  def add(%{queue: queue} = flow_control, request) do
    queue = :queue.in(request, queue)
    %{flow_control | queue: queue}
  end

  @spec process(t, Config.t()) :: t
  def process(%{queue: queue} = flow, config) do
    with {{:value, request}, queue} <- :queue.out(queue),
         {:can_send, true} <- {:can_send, can_send?(flow)} do
      %{
        initial_window_size: window,
        max_frame_size: max_frame
      } = flow

      stream = Stream.new(config, flow.stream_id, window, max_frame)

      case Stream.start_link(stream) do
        {:ok, pid} ->
          size = byte_size(request.body || <<>>)
          :gen_statem.call(pid, {:send_headers, request})

          flow
          |> Map.put(:queue, queue)
          |> decrement_window(size)
          |> add_active(flow.stream_id, pid)
          |> increment_active_stream_count()
          |> increment_stream_id()
          |> process(config)

        other ->
          raise "something happened #{inspect(other)}"
          flow
      end
    else
      {:empty, _queue} -> flow
      {:can_send, false} -> flow
    end
  end

  @doc ~S"""
  Returns true if active_streams is less than max streams and window
  is positive.

  ## Examples

      iex> flow = %Kadabra.Connection.FlowControl{active_stream_count: 3,
      ...> max_concurrent_streams: 100, window: 500}
      iex> can_send?(flow)
      true

      iex> flow = %Kadabra.Connection.FlowControl{active_stream_count: 3,
      ...> max_concurrent_streams: 100, window: 0}
      iex> can_send?(flow)
      false

      iex> flow = %Kadabra.Connection.FlowControl{active_stream_count: 3,
      ...> max_concurrent_streams: 1, window: 500}
      iex> can_send?(flow)
      false
  """
  @spec can_send?(t) :: boolean
  def can_send?(%{
        active_stream_count: count,
        max_concurrent_streams: max,
        window: bytes
      })
      when count < max and bytes > 0,
      do: true

  def can_send?(_else), do: false
end
