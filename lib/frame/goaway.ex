defmodule Kadabra.Frame.Goaway do
  @moduledoc false

  defstruct [:last_stream_id, :error_code, :debug_data]

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
      debug_data: nil}
  """
  @spec new(non_neg_integer) :: t
  def new(stream_id) when is_integer(stream_id) do
    %__MODULE__{
      last_stream_id: stream_id,
      error_code: Error.no_error()
    }
  end

  @spec new(Frame.t()) :: t
  def new(%Frame{payload: payload}) do
    <<
      _r::1,
      last_stream_id::31,
      error_code::32,
      debug_data::bitstring
    >> = payload

    %__MODULE__{
      last_stream_id: last_stream_id,
      error_code: error_code,
      debug_data: debug_data
    }
  end

  def new(stream_id, error_code) when is_integer(stream_id) do
    new(stream_id, error_code, nil)
  end

  def new(stream_id, error_code, reason) when is_integer(stream_id) do
    %__MODULE__{
      last_stream_id: stream_id,
      error_code: error_code,
      debug_data: reason
    }
  end
end

defimpl Kadabra.Encodable, for: Kadabra.Frame.Goaway do
  alias Kadabra.Frame

  @goaway 0x7

  def to_bin(%{last_stream_id: id, error_code: error}) do
    payload = <<0::1, id::31>> <> error
    Frame.binary_frame(@goaway, 0x0, 0, payload)
  end
end
