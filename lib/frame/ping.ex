defmodule Kadabra.Frame.Ping do
  defstruct [:data, ack: false]

  alias Kadabra.Frame
  alias Kadabra.Frame.Flags

  def new do
    %__MODULE__{
      data: <<0, 0, 0, 0, 0, 0, 0, 0>>,
      ack: false
    }
  end

  def new(%Frame{type: 0x6, payload: data, flags: flags}) do
    %__MODULE__{
      data: data,
      ack: Flags.ack?(flags)
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
end

defimpl Kadabra.Encodable, for: Kadabra.Frame.Ping do
  alias Kadabra.Http2
  alias Kadabra.Frame.Flags

  def to_bin(frame) do
    ack = if frame.ack, do: Flags.ack, else: 0x0
    Http2.build_frame(0x6, ack, 0x0, frame.data)
  end
end
