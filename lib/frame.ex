defmodule Kadabra.Frame do
  defstruct [:length, :type, :flags, :stream_id, :payload]

  @data 0x0
  @headers 0x1
  @rst_stream 0x3
  @settings 0x4
  @push_promise 0x5
  @ping 0x6
  @goaway 0x7
  @window_update 0x8
  @continuation 0x9

  @type t :: %__MODULE__{
    length: non_neg_integer,
    type: non_neg_integer,
    flags: <<_::8>>,
    stream_id: non_neg_integer,
    payload: bitstring
  }

  def new(<<payload_size::24,
            frame_type::8,
            flags::8,
            0::1,
            stream_id::31,
            payload::bitstring>> = bin) do

    size = payload_size * 8

    case parse_payload(size, payload) do
      {:ok, frame_payload, rest} ->
        {:ok, %Kadabra.Frame{
          length: payload_size,
          type: frame_type,
          flags: <<flags::8>>,
          stream_id: stream_id,
          payload: frame_payload
        }, rest}
      {:error, _bin} ->
        {:error, bin}
    end
  end
  def new(bin), do: {:error, bin}

  def parse_payload(size, bin) do
    case bin do
      <<frame_payload::size(size), rest::bitstring>> ->
        {:ok, <<frame_payload::size(size)>>, <<rest::bitstring>>}
      bin -> {:error, <<bin::bitstring>>}
    end
  end
end
