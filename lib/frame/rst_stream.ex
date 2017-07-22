defmodule Kadabra.Frame.RstStream do
  defstruct [:stream_id, :error_code]

  alias Kadabra.{Error, Frame}

  @type t :: %__MODULE__{
    error_code: <<_::32>>,
    stream_id: non_neg_integer
  }

  @spec new(non_neg_integer) :: t
  def new(stream_id) when is_integer(stream_id) do
    %__MODULE__{stream_id: stream_id, error_code: Error.no_error}
  end

  @spec new(Frame.t) :: t
  def new(%{stream_id: stream_id, payload: error_code}) do
    %__MODULE__{
      stream_id: stream_id,
      error_code: error_code
    }
  end
end

defimpl Kadabra.Encodable, for: Kadabra.Frame.RstStream do
  alias Kadabra.Http2

  def to_bin(frame) do
    Http2.build_frame(0x3, 0x0, frame.stream_id, frame.error_code)
  end
end
