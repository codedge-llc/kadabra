defmodule Kadabra.Stream.FlowControl do
  @moduledoc false

  defstruct queue: [],
            window: 56_536,
            max_frame_size: 16_384,
            stream_id: nil

  alias Kadabra.{Encodable, Frame}

  @type t :: %__MODULE__{
    max_frame_size: non_neg_integer,
    queue: [] | [...],
    window: integer
  }

  @type sock :: {:sslsocket, any, pid | {any, any}}

  @type frame :: {:send, binary}

  @doc ~S"""
  Returns new `Kadabra.Stream.FlowControl` with given opts.

  ## Examples

      iex> new(stream_id: 1)
      %Kadabra.Stream.FlowControl{stream_id: 1}
  """
  @spec new(Keyword.t) :: t
  def new(opts \\ []) do
    %__MODULE__{
      stream_id: opts[:stream_id],
      window: opts[:window] || 56_536
    }
  end

  @doc ~S"""
  Enqueues a sendable payload.

  ## Examples

      iex> add(%Kadabra.Stream.FlowControl{}, "test")
      %Kadabra.Stream.FlowControl{queue: [{:send, "test"}]}
  """
  @spec add(t, binary) :: t
  def add(flow_control, bin) do
    queue = flow_control.queue ++ [{:send, bin}]
    %{flow_control | queue: queue}
  end

  @doc ~S"""
  Processes sendable data in queue, if any present and window
  is positive.

  ## Examples

      iex> process(%Kadabra.Stream.FlowControl{queue: []}, self())
      %Kadabra.Stream.FlowControl{queue: []}

      iex> process(%Kadabra.Stream.FlowControl{queue: [{:send, "test"}],
      ...> window: -20}, self())
      %Kadabra.Stream.FlowControl{queue: [{:send, "test"}], window: -20}
  """
  @spec process(t, sock) :: t
  def process(%{queue: []} = flow_control, _sock) do
    flow_control
  end
  def process(%{window: window} = flow_control, _sock) when window <= 0 do
    flow_control
  end
  def process(%{queue: [{:send, bin} | rest],
								max_frame_size: max_size,
                window: window,
                stream_id: stream_id} = flow_control, socket) do

    size = byte_size(bin)

    if size > window do
      {chunk, rem_bin} = :erlang.split_binary(bin, window)

      max_size
      |> split_packet(chunk)
      |> send_partial_data(socket, stream_id)

      flow_control = %{flow_control |
        queue: [{:send, rem_bin} | rest],
        window: 0
      }
      process(flow_control, socket)
    else
      max_size
      |> split_packet(bin)
      |> send_data(socket, stream_id)

      flow_control = %{flow_control | queue: rest, window: window - size}
      process(flow_control, socket)
    end
  end

  def send_partial_data([], _socket, _stream_id), do: :ok
  def send_partial_data([bin | rest], socket, stream_id) do
    p =
      %Frame.Data{stream_id: stream_id, end_stream: false, data: bin}
      |> Encodable.to_bin
    :ssl.send(socket, p)
    send_partial_data(rest, socket, stream_id)
  end

  def send_data([], _socket, _stream_id), do: :ok
  def send_data([bin | []], socket, stream_id) do
    p =
      %Frame.Data{stream_id: stream_id, end_stream: true, data: bin}
      |> Encodable.to_bin
    :ssl.send(socket, p)
    send_data([], socket, stream_id)
  end
  def send_data([bin | rest], socket, stream_id) do
    p =
      %Frame.Data{stream_id: stream_id, end_stream: false, data: bin}
      |> Encodable.to_bin
    :ssl.send(socket, p)
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
end
