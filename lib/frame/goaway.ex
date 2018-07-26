defmodule Kadabra.Frame.Goaway do
  @moduledoc false

  defstruct last_stream_id: nil, error_code: nil, debug_data: <<>>

  alias Kadabra.{Error, Frame}

  @type t :: %__MODULE__{
          debug_data: bitstring,
          error_code: <<_::32>>,
          last_stream_id: non_neg_integer
        }

  @doc ~S"""
  Initializes a new GOAWAY frame with no error.

  ## Examples

      iex> Kadabra.Frame.Goaway.new(3)
      %Kadabra.Frame.Goaway{last_stream_id: 3, error_code: <<0, 0, 0, 0>>,
      debug_data: <<>>}
  """
  @spec new(non_neg_integer) :: t
  def new(stream_id) when is_integer(stream_id) do
    %__MODULE__{
      last_stream_id: stream_id,
      error_code: Error.no_error()
    }
  end

  @spec new(Frame.t()) :: t
  def new(%Frame{payload: <<_r::1, sid::31, error::32, debug::bitstring>>}) do
    %__MODULE__{
      last_stream_id: sid,
      error_code: <<error::32>>,
      debug_data: debug
    }
  end

  @spec new(non_neg_integer, <<_::32>>) :: t
  def new(stream_id, error_code) when is_integer(stream_id) do
    new(stream_id, error_code, <<>>)
  end

  @spec new(non_neg_integer, <<_::32>>, bitstring) :: t
  def new(stream_id, error_code, reason) when is_integer(stream_id) do
    %__MODULE__{
      last_stream_id: stream_id,
      error_code: error_code,
      debug_data: reason
    }
  end
end
