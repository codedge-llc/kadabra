defmodule Kadabra.Frame.WindowUpdate do
  @moduledoc false

  defstruct [:stream_id, :window_size_increment]

  alias Kadabra.Frame

  @type t :: %__MODULE__{
          stream_id: non_neg_integer,
          window_size_increment: non_neg_integer
        }

  @spec new(Frame.t()) :: t
  def new(%Frame{payload: <<inc::32>>, stream_id: stream_id}) do
    %__MODULE__{
      window_size_increment: inc,
      stream_id: stream_id
    }
  end

  @spec new(non_neg_integer, pos_integer | binary) :: t
  def new(stream_id, increment) when is_integer(increment) do
    %__MODULE__{
      stream_id: stream_id,
      window_size_increment: increment
    }
  end
end
