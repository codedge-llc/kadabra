defmodule Kadabra.Frame.RstStream do
  @moduledoc false

  defstruct [:stream_id, :error_code]

  alias Kadabra.{Error, Frame}

  @type t :: %__MODULE__{
          error_code: <<_::32>>,
          stream_id: non_neg_integer
        }

  @spec new(non_neg_integer) :: t
  def new(stream_id) when is_integer(stream_id) do
    %__MODULE__{stream_id: stream_id, error_code: Error.no_error()}
  end

  @doc ~S"""
  Initializes a new `Frame.RstStream` given a `Frame`.

  ## Examples

      iex> frame = %Kadabra.Frame{payload: <<0, 0, 0, 0, 0, 0, 0, 0>>,
      ...> flags: 0x1, type: 0x3, stream_id: 1}
      iex> Kadabra.Frame.RstStream.new(frame)
      %Kadabra.Frame.RstStream{
        error_code: <<0, 0, 0, 0, 0, 0, 0, 0>>,
        stream_id: 1
      }
  """
  @spec new(Frame.t()) :: t
  def new(%Frame{stream_id: stream_id, payload: error_code}) do
    %__MODULE__{
      stream_id: stream_id,
      error_code: error_code
    }
  end
end
