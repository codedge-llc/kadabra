defmodule Kadabra.Frame.WindowUpdate do
  @moduledoc false

  defstruct [:stream_id, :window_size_increment]

  alias Kadabra.Frame

  @type t :: %__MODULE__{
          stream_id: non_neg_integer,
          window_size_increment: non_neg_integer
        }

  @spec new(Frame.t() | binary) :: t
  def new(%Frame{payload: <<inc::32>>, stream_id: stream_id}) do
    %__MODULE__{
      window_size_increment: inc,
      stream_id: stream_id
    }
  end

  def new(bin) do
    new(0x0, bin)
  end

  @spec new(non_neg_integer, pos_integer | binary) :: t
  def new(stream_id, increment) when is_integer(increment) do
    %__MODULE__{
      stream_id: stream_id,
      window_size_increment: increment
    }
  end

  def new(stream_id, bin) when is_binary(bin) do
    new(stream_id, byte_size(bin))
  end
end

defimpl Kadabra.Encodable, for: Kadabra.Frame.WindowUpdate do
  alias Kadabra.Frame

  @window_update 0x8

  def to_bin(frame) do
    size = <<frame.window_size_increment::32>>
    Frame.binary_frame(@window_update, 0x0, frame.stream_id, size)
  end
end
