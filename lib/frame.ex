defmodule Kadabra.Frame do
  @moduledoc false

  defstruct [:length, :type, :flags, :stream_id, :payload]

  @type t :: %__MODULE__{
          length: non_neg_integer,
          type: non_neg_integer,
          flags: non_neg_integer,
          stream_id: non_neg_integer,
          payload: bitstring
        }

  @spec new(binary) :: {:ok, t, binary} | {:error, binary}
  def new(<<p_size::24, type::8, f::8, 0::1, s_id::31, p::bitstring>> = bin) do
    size = p_size * 8

    case parse_payload(size, p) do
      {:ok, frame_payload, rest} ->
        frame = %__MODULE__{
          length: p_size,
          type: type,
          flags: f,
          stream_id: s_id,
          payload: frame_payload
        }

        {:ok, frame, rest}

      {:error, _bin} ->
        {:error, bin}
    end
  end

  def new(bin), do: {:error, bin}

  defp parse_payload(size, bin) do
    case bin do
      <<frame_payload::size(size), rest::bitstring>> ->
        {:ok, <<frame_payload::size(size)>>, <<rest::bitstring>>}

      bin ->
        {:error, <<bin::bitstring>>}
    end
  end

  @spec binary_frame(integer, integer, integer, binary) :: binary
  def binary_frame(frame_type, flags, stream_id, payload) do
    size = byte_size(payload)
    header = <<size::24, frame_type::8, flags::8, 0::1, stream_id::31>>
    <<header::bitstring, payload::bitstring>>
  end
end

defimpl Kadabra.Encodable, for: Kadabra.Frame do
  alias Kadabra.Frame

  def to_bin(%{type: type, flags: flags, stream_id: sid, payload: p}) do
    Frame.binary_frame(type, flags, sid, p)
  end
end
