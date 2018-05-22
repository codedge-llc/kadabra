defmodule Kadabra.Stream.FlowControl do
  @moduledoc false

  alias Kadabra.Packetizer

  @default_max_frame round(:math.pow(2, 14))
  @default_window round(:math.pow(2, 16) - 1)

  defstruct queue: :queue.new(),
            out_queue: :queue.new(),
            window: @default_window,
            max_frame_size: @default_max_frame

  @type t :: %__MODULE__{
          max_frame_size: non_neg_integer,
          queue: :queue.queue(binary),
          out_queue: :queue.queue({binary, boolean}),
          window: integer
        }

  @type sock :: {:sslsocket, any, pid | {any, any}}

  @type frame :: {:send, binary}

  @doc ~S"""
  Returns new `Kadabra.Stream.FlowControl` with given opts.

  ## Examples

      iex> new()
      %Kadabra.Stream.FlowControl{}

      iex> new(window: 20_000, max_frame_size: 18_000)
      %Kadabra.Stream.FlowControl{window: 20_000, max_frame_size: 18_000}
  """
  @spec new(Keyword.t()) :: t
  def new(opts \\ []) do
    %__MODULE__{
      window: Keyword.get(opts, :window, @default_window),
      max_frame_size: Keyword.get(opts, :max_frame_size, @default_max_frame)
    }
  end

  @doc ~S"""
  Enqueues a sendable payload.

  ## Examples

      iex> add(%Kadabra.Stream.FlowControl{}, "test")
      %Kadabra.Stream.FlowControl{queue: {["test"], []}}
  """
  @spec add(t, binary) :: t
  def add(flow_control, bin) do
    queue = :queue.in(bin, flow_control.queue)
    Map.put(flow_control, :queue, queue)
  end

  @doc ~S"""
  Processes sendable data in queue, if any present and window
  is positive.

  ## Examples

      iex> process(%Kadabra.Stream.FlowControl{queue: :queue.new()})
      %Kadabra.Stream.FlowControl{queue: {[], []}}

      iex> queue = :queue.in({:send, "test"}, :queue.new())
      iex> process(%Kadabra.Stream.FlowControl{queue: queue, window: -20})
      %Kadabra.Stream.FlowControl{queue: {[send: "test"], []}, window: -20}
  """
  @spec process(t) :: t
  def process(%{window: window} = flow_control) when window <= 0 do
    flow_control
  end

  def process(%{queue: queue} = flow_control) do
    case :queue.out(queue) do
      {{:value, bin}, queue} ->
        flow_control
        |> Map.put(:queue, queue)
        |> do_process(bin)

      {:empty, _queue} ->
        flow_control
    end
  end

  defp do_process(%{window: window} = flow, bin) when byte_size(bin) > window do
    %{
      queue: queue,
      out_queue: out_queue,
      max_frame_size: max_size
    } = flow

    {chunk, rem_bin} = :erlang.split_binary(bin, window)

    payloads = Packetizer.split(max_size, chunk)
    out_queue = enqueue_partial(out_queue, payloads)

    queue = :queue.in_r(rem_bin, queue)

    flow
    |> Map.put(:queue, queue)
    |> Map.put(:out_queue, out_queue)
    |> Map.put(:window, 0)
    |> process()
  end

  defp do_process(%{window: window} = flow_control, bin) do
    %{max_frame_size: max_size, out_queue: out_queue} = flow_control

    payloads = Packetizer.split(max_size, bin)
    out_queue = enqueue_complete(out_queue, payloads)

    flow_control
    |> Map.put(:window, window - byte_size(bin))
    |> Map.put(:out_queue, out_queue)
    |> process()
  end

  @doc ~S"""
  Increments stream window by given increment.

  ## Examples

      iex> increment_window(%Kadabra.Stream.FlowControl{window: 0}, 736)
      %Kadabra.Stream.FlowControl{window: 736}
  """
  @spec increment_window(t, pos_integer) :: t
  def increment_window(flow_control, amount) do
    %{flow_control | window: flow_control.window + amount}
  end

  @doc ~S"""
  Sets stream max_frame_size to given size.

  ## Examples

      iex> set_max_frame_size(%Kadabra.Stream.FlowControl{
      ...> max_frame_size: 16_384}, 1_040_200)
      %Kadabra.Stream.FlowControl{max_frame_size: 1_040_200}
  """
  @spec set_max_frame_size(t, pos_integer) :: t
  def set_max_frame_size(flow_control, size) do
    %{flow_control | max_frame_size: size}
  end

  defp enqueue_complete(queue, []), do: queue

  defp enqueue_complete(queue, [payload | []]) do
    {payload, true}
    |> :queue.in(queue)
    |> enqueue_complete([])
  end

  defp enqueue_complete(queue, [payload | rest]) do
    {payload, false}
    |> :queue.in(queue)
    |> enqueue_complete(rest)
  end

  defp enqueue_partial(queue, []), do: queue

  defp enqueue_partial(queue, [payload | rest]) do
    {payload, false}
    |> :queue.in(queue)
    |> enqueue_partial(rest)
  end
end
