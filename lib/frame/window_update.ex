defmodule Kadabra.Frame.WindowUpdate do
  defstruct [:stream_id, :window_size_increment]

  alias Kadabra.Frame

  @type t :: %__MODULE__{
    stream_id: non_neg_integer,
    window_size_increment: non_neg_integer
  }

  @spec new(Frame.t) :: t
  def new(%Frame{payload: p, stream_id: stream_id}) do
    %__MODULE__{
      window_size_increment: p,
      stream_id: stream_id
    }
  end
end
