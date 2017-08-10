defmodule Kadabra.Http2 do
  @moduledoc """
  Handles all HTTP2 connection, request and response functions.
  """
  require Logger

  def connection_preface, do: "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
  def settings_ack_frame, do: build_frame(0x04, 0x01, 0, <<>>)
  def ack_frame, do: build_frame(0x01, 0, 0, <<>>)
  def ping_frame, do: build_frame(0x6, 0x0, 0, <<1::64>>)

  def goaway_frame(last_stream_id, error_code) do
    payload = <<0::1, last_stream_id::31, error_code::32>>
    build_frame(0x7, 0x0, 0, payload)
  end

  def settings_frame do
    headers = [
      # {"SETTINGS_HEADER_TABLE_SIZE", Integer.to_string(4096)},
      # {"SETTINGS_MAX_CONCURRENT_STREAMS", Integer.to_string(500)},
      # {"SETTINGS_MAX_FRAME_SIZE", Integer.to_string(16384)},
      # {"SETTINGS_MAX_HEADER_LIST_SIZE", Integer.to_string(8000)}
      # {"SETTINGS_INITIAL_WINDOW_SIZE", Integer.to_string(1_048_576)}
    ]
    encoded = for {key, value} <- headers, do: encode_header(key, value)
    headers_payload = Enum.reduce(encoded, <<>>, fn(x, acc) -> acc <> x end)
    build_frame(0x4, 0x0, 0, headers_payload)
  end

  def build_frame(frame_type, flags, stream_id, payload) do
    header = <<
      byte_size(payload)::24,
      frame_type::8,
      flags::8,
      0::1,
      stream_id::31
    >>
    <<header::bitstring, payload::bitstring>>
  end

  def parse_frame(<<payload_size::24,
                    frame_type::8,
                    flags::8,
                    0::1,
                    stream_id::31,
                    payload::bitstring>> = full_bin) do

    size = payload_size * 8

    case parse_payload(size, payload) do
      {:ok, frame_payload, rest} ->
        {:ok, %{
          payload_size: payload_size,
          frame_type: frame_type,
          flags: flags,
          stream_id: stream_id,
          payload: frame_payload
        }, rest}
      {:error, _bin} ->
        {:error, full_bin}
    end
  end
  def parse_frame(bin), do: {:error, bin}

  def parse_payload(size, bin) do
    case bin do
      <<frame_payload::size(size), rest::bitstring>> ->
        {:ok, <<frame_payload::size(size)>>, <<rest::bitstring>>}
      bin -> {:error, <<bin::bitstring>>}
    end
  end

  def post_header, do: <<1::1, 0::1, 0::1, 0::1, 0::1, 0::1, 1::1, 1::1>>
  def https_header, do: <<1::1, 0::1, 0::1, 0::1, 0::1, 1::1, 1::1, 1::1>>

  def encode_header(header, value) do
    <<0::1, 0::1, 0::1, 1::1, 0::4, 0::1, byte_size(header)::7>>
    <> header
    <> <<0::1, byte_size(value)::7>>
    <> value
  end

  def encode_header_incremental_indexing(name, value) do
    <<0::1, 1::1, 0::6>>
    <> <<0::1, byte_size(name)::7>>
    <> name
    <> <<0::1, byte_size(value)::7>>
    <> value
  end
end
