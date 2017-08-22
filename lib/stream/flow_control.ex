defmodule Kadabra.Stream.FlowControl do
  @moduledoc false

  defstruct queue: [],
            window: 56_536,
            max_frame_size: 16_536,
            stream_id: nil

  alias Kadabra.Http2

  @type t :: %__MODULE__{
    max_frame_size: non_neg_integer,
    queue: [...],
    window: integer
  }

  @type sock :: {:sslsocket, any, pid | {any, any}}

  @type frame :: {:send, binary}

  @data 0x0

  def new(stream_id) do
    %__MODULE__{
      stream_id: stream_id
    }
  end

  @spec add(t, frame) :: t
  def add(flow_control, bin) do
    queue = flow_control.queue ++ [{:send, bin}]
    %{flow_control | queue: queue}
  end

  @spec process(t, sock) :: t
  def process(%{queue: []} = flow_control, _sock) do
    flow_control
  end
  def process(%{window: window} = flow_control, _sock) when window <= 0 do
    flow_control
  end
  def process(%{queue: [{:send, bin} | rest],
                window: window,
                stream_id: stream_id} = flow_control, socket) do

    size = byte_size(bin)

    if size > window do
      {chunk, rem_bin} = :erlang.split_binary(bin, window)
      p = Http2.build_frame(@data, 0x0, stream_id, chunk)
      :ssl.send(socket, p)

      flow_control = %{flow_control |
        queue: [{:send, rem_bin} | rest],
        window: 0
      }
      process(flow_control, socket)
    else
      p = Http2.build_frame(@data, 0x1, stream_id, bin)
      :ssl.send(socket, p)

      flow_control = %{flow_control | queue: rest, window: window - size}
      process(flow_control, socket)
    end
  end

  def increment_window(flow_control, amount) do
    %{flow_control | window: flow_control.window + amount}
  end
end
