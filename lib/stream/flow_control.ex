defmodule Kadabra.Stream.FlowControl do
  @moduledoc false

  @default_window_size 65_535

  defstruct queue: :queue.new(),
            window: @default_window_size,
            max_frame_size: 16_384,
            socket: nil,
            stream_id: nil

  alias Kadabra.{Encodable, Frame, Socket}

  @type t :: %__MODULE__{
          max_frame_size: non_neg_integer,
          queue: :queue.queue(binary),
          socket: pid,
          window: integer
        }

  @type sock :: {:sslsocket, any, pid | {any, any}}

  @type frame :: {:send, binary}

  @doc ~S"""
  Returns new `Kadabra.Stream.FlowControl` with given opts.

  ## Examples

      iex> new(stream_id: 1)
      %Kadabra.Stream.FlowControl{stream_id: 1}

      iex> new(stream_id: 1, window: 20_000, max_frame_size: 18_000)
      %Kadabra.Stream.FlowControl{stream_id: 1, window: 20_000,
      max_frame_size: 18_000}
  """
  @spec new(Keyword.t()) :: t
  def new(opts \\ []) do
    %__MODULE__{
      stream_id: Keyword.get(opts, :stream_id),
      socket: Keyword.get(opts, :socket),
      window: Keyword.get(opts, :window, @default_window_size),
      max_frame_size: Keyword.get(opts, :max_frame_size, 16_384)
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
      max_frame_size: max_size,
      socket: socket,
      stream_id: stream_id
    } = flow

    {chunk, rem_bin} = :erlang.split_binary(bin, window)

    max_size
    |> split_packet(chunk)
    |> send_partial_data(socket, stream_id)

    queue = :queue.in_r(rem_bin, queue)

    flow
    |> Map.put(:queue, queue)
    |> Map.put(:window, 0)
    |> process()
  end

  defp do_process(%{window: window} = flow_control, bin) do
    %{
      max_frame_size: max_size,
      socket: socket,
      stream_id: stream_id
    } = flow_control

    max_size
    |> split_packet(bin)
    |> send_data(socket, stream_id)

    flow_control
    |> Map.put(:window, window - byte_size(bin))
    |> process()
  end

  def send_partial_data([], _socket, _stream_id), do: :ok

  def send_partial_data([bin | rest], socket, stream_id) do
    p =
      %Frame.Data{stream_id: stream_id, end_stream: false, data: bin}
      |> Encodable.to_bin()

    Socket.send(socket, p)
    send_partial_data(rest, socket, stream_id)
  end

  def send_data([], _socket, _stream_id), do: :ok

  def send_data([bin | []], socket, stream_id) do
    p =
      %Frame.Data{stream_id: stream_id, end_stream: true, data: bin}
      |> Encodable.to_bin()

    Socket.send(socket, p)
    send_data([], socket, stream_id)
  end

  def send_data([bin | rest], socket, stream_id) do
    p =
      %Frame.Data{stream_id: stream_id, end_stream: false, data: bin}
      |> Encodable.to_bin()

    Socket.send(socket, p)
    send_data(rest, socket, stream_id)
  end

  def split_packet(size, p) when byte_size(p) >= size do
    {chunk, rest} = :erlang.split_binary(p, size)
    [chunk | split_packet(size, rest)]
  end

  def split_packet(_size, <<>>), do: []
  def split_packet(_size, p), do: [p]

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
end
