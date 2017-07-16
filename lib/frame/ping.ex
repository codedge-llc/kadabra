defmodule Kadabra.Frame.Ping do
  defstruct [:data, ack: false]

  alias Kadabra.Http2

  def new do
    %__MODULE__{
      data: <<0, 0, 0, 0, 0, 0, 0, 0>>,
      ack: false
    }
  end

  def new(%{payload: data, flags: flags}) do
    %__MODULE__{
      data: data,
      ack: (flags == 0x1)
    }
  end

  def new(opts) do
    %__MODULE__{
      data: opts[:data],
      ack: opts[:ack]
    }
  end

  def ack_flag(%{ack: true}), do: 0x1
  def ack_flag(%{ack: false}), do: 0x0

  def to_bin(frame) do
    Http2.build_frame(0x6, ack_flag(frame), 0x0, frame.data)
  end
end
