defmodule Kadabra.Connection.FlowControl do
  @moduledoc false

  @default_window_size round(:math.pow(2, 16) - 1)
  @max_window_size round(:math.pow(2, 31) - 1)

  @default_initial_window_size round(:math.pow(2, 16) - 1)
  @default_max_frame_size round(:math.pow(2, 14))

  defstruct queue: :queue.new(),
            stream_set: %Kadabra.StreamSet{},
            initial_window_size: @default_initial_window_size,
            max_frame_size: @default_max_frame_size,
            window: @default_window_size

  alias Kadabra.{Config, Stream, StreamSet}

  @type t :: %__MODULE__{
          queue: :queue.queue(),
          stream_set: StreamSet.t(),
          initial_window_size: non_neg_integer,
          max_frame_size: non_neg_integer,
          window: integer
        }

  def window_default, do: @default_window_size

  def window_max, do: @max_window_size

  @spec update_settings(t(), integer, integer, integer) :: t()
  def update_settings(flow_control, initial_window, max_frame, max_streams) do
    new_set =
      Map.put(flow_control.stream_set, :max_concurrent_streams, max_streams)

    flow_control
    |> Map.put(:initial_window_size, initial_window)
    |> Map.put(:max_frame_size, max_frame)
    |> Map.put(:stream_set, new_set)
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

  def add_active(%{stream_set: set} = flow_control, stream_id, pid) do
    new_set = StreamSet.add_active(set, stream_id, pid)
    %{flow_control | stream_set: new_set}
  end

  @spec process(t, Config.t()) :: t
  def process(%{queue: queue, stream_set: stream_set} = flow, config) do
    with {{:value, request}, queue} <- :queue.out(queue),
         {:can_send, true} <- {:can_send, StreamSet.can_send?(stream_set)},
         {:can_send, true} <- {:can_send, can_send?(flow)} do
      %{
        stream_set: %{stream_id: stream_id},
        initial_window_size: window,
        max_frame_size: max_frame
      } = flow

      stream = Stream.new(config, stream_id, window, max_frame)

      case Stream.start_link(stream) do
        {:ok, pid} ->
          Process.monitor(pid)

          size = byte_size(request.body || <<>>)
          :gen_statem.call(pid, {:send_headers, request})

          updated_set = add_stream(stream_set, stream_id, pid)

          flow
          |> Map.put(:queue, queue)
          |> Map.put(:stream_set, updated_set)
          |> decrement_window(size)
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

  defp add_stream(stream_set, stream_id, pid) do
    stream_set
    |> StreamSet.add_active(stream_id, pid)
    |> StreamSet.increment_active_stream_count()
    |> StreamSet.increment_stream_id()
  end

  @spec finish_stream(t, non_neg_integer) :: t
  def finish_stream(%{stream_set: set} = flow_control, stream_id) do
    new_set =
      set
      |> StreamSet.decrement_active_stream_count()
      |> StreamSet.remove_active(stream_id)

    %{flow_control | stream_set: new_set}
  end

  @doc ~S"""
  Returns true if window is positive.

  ## Examples

      iex> flow = %Kadabra.Connection.FlowControl{window: 500}
      iex> can_send?(flow)
      true

      iex> flow = %Kadabra.Connection.FlowControl{window: 0}
      iex> can_send?(flow)
      false
  """
  @spec can_send?(t) :: boolean
  def can_send?(%{window: bytes}) when bytes > 0, do: true
  def can_send?(_else), do: false
end
