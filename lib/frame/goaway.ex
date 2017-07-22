defmodule Kadabra.Frame.Goaway do
  defstruct [:last_stream_id, :error_code, :debug_data]

  alias Kadabra.{Error, Frame}

  @type t :: %__MODULE__{
    debug_data: bitstring,
    error_code: <<_::32>>,
    last_stream_id: non_neg_integer,
  }

  @spec new(non_neg_integer) :: t
  def new(stream_id) when is_integer(stream_id) do
    %__MODULE__{
      last_stream_id: stream_id,
      error_code: Error.no_error
    }
  end

  @spec new(Frame.t) :: t
  def new(%Frame{payload: <<_r::1,
                            last_stream_id::31,
                            error_code::32,
                            debug_data::bitstring>>}) do
    %__MODULE__{
      last_stream_id: last_stream_id,
      error_code: error_code,
      debug_data: debug_data
    }
  end
end

defimpl Kadabra.Encodable, for: Kadabra.Frame.Goaway do
  alias Kadabra.Http2

  def to_bin(%{last_stream_id: id, error_code: error}) do
    payload = <<0::1, id::31>> <> error
    Http2.build_frame(0x7, 0x0, 0, payload)
  end
end
