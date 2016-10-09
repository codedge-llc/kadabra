defmodule Kadabra.Http2 do
  @moduledoc """
    Handles all HTTP2 connection, request and response functions.
  """
  require Logger

  alias Kadabra.{Hpack, Huffman}

  def connection_preface, do: "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
  def settings_ack_frame, do: build_frame(0x04, 0x01, 0, <<>>)
  def ack_frame, do: build_frame(0x01, 0, 0, <<>>)
  def ping_frame, do: build_frame(0x6, 0x0, 0, <<1::64>>)

  def goaway_frame(last_stream_id, error_code) do
    payload = <<0::1, last_stream_id::31, error_code::32>>
    build_frame(0x7, 0x0, 0, payload)
    |> IO.inspect
  end

  def settings_frame do
    headers = [
      #{"SETTINGS_HEADER_TABLE_SIZE", Integer.to_string(4096)},
      #{"SETTINGS_MAX_CONCURRENT_STREAMS", Integer.to_string(500)},
      #{"SETTINGS_MAX_FRAME_SIZE", Integer.to_string(16384)},
      #{"SETTINGS_MAX_HEADER_LIST_SIZE", Integer.to_string(8000)}
    ]
    encoded = for {key, value} <- headers, do: encode_header(key, value)
    headers_payload = Enum.reduce(encoded, <<>>, fn(x, acc) -> acc <> x end)
    build_frame(0x4, 0x0, 0, headers_payload)
  end

  def build_frame(frame_type, flags, stream_id, payload) do
    Logger.warn "Size: #{byte_size(payload)}"
    header = <<byte_size(payload)::24, frame_type::8, flags::8, 0::1, stream_id::31>>
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
          #payload: <<frame_payload::size(size)>>
        }, rest}
      {:error, bin} -> {:error, full_bin}
    end
  end
  def parse_frame(bin), do: {:error, bin}

  def parse_payload(size, bin) do
    case bin do
      <<frame_payload::size(size), rest::bitstring>> ->
        {:ok, <<frame_payload::size(size)>>, rest}
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

  def decode_headers(<<>>), do: []
  def decode_headers(bin) do
    {header, rest} =
      case bin do
      <<1::1, _rest::bitstring>> -> indexed_header(bin)
      <<0::1, 1::1, _rest::bitstring>> -> literal_header_inc_indexing(bin) 
      <<0::4, _rest::bitstring>> -> literal_header_no_indexing(bin)
      <<0::3, 0::1, _rest::bitstring>> -> literal_header_never_indexed(bin)
      <<0::2, 0::1, _rest::bitstring>> -> dynamic_table_size_update(bin)
      end
    [header] ++ decode_headers(rest)
  end

  defp decode_value(0, _size, value), do: value
  defp decode_value(1, size, value), do: <<value::size(size)>> |> Huffman.decode |> inspect

  def indexed_header(<<1::1, index::7, rest::bitstring>>), do: {Hpack.static_header(index), rest}

  def literal_header_inc_indexing(<<0::1, 1::1, 0::6, h::1, name_size::7, rest::bitstring>>) do # New name
    name_size = name_size * 8
    <<name::size(name_size), rest::bitstring>> = rest
    name_string = decode_value(h, name_size, name)

    <<_h_2::1, value_size::7, rest::bitstring>> = rest
    value_size = value_size * 8
    <<value::size(value_size), rest::bitstring>> = rest
    value_string = decode_value(h, value_size, value)

    # Logger.info("Literal, Inc Indexing New Name, H: #{h}, H2: #{h_2}, Name: #{name_string}, Value: #{value_string}")
    {{name_string, value_string}, rest}
  end
  def literal_header_inc_indexing(<<0::1, 1::1, index::6, h::1, value_size::7, rest::bitstring>>) do
    value_size = value_size*8
    IO.inspect "<<value::size(#{value_size}), rest::bitstring>> = #{inspect(rest)}"
    <<value::size(value_size), rest::bitstring>> = rest
    value_string = decode_value(h, value_size, value)
    header_string = Hpack.static_header(index)
    # Logger.info("Literal, Inc Indexing, H: #{h}, Header: #{header_string}, Value: #{value_string}")
    {{header_string, value_string}, rest}
  end

  def literal_header_no_indexing(<<0::4, 0::4, _h::1, name_size::7, rest::bitstring>>) do # New name
    name_size = name_size * 8
    <<name::size(name_size), rest::bitstring>> = rest
    <<_h_2::1, value_size::7, rest::bitstring>> = rest
    value_size = value_size * 8
    <<value::size(value_size), rest::bitstring>> = rest
    # Logger.info("Literal No Indexing, New Name, H: #{h}, #{inspect(<<value::size(value_size)>>)}")
    {{name, value}, rest}
  end
  def literal_header_no_indexing(<<0::4, index::4, _h::1, value_size::7, rest::bitstring>>) do
    value_size = value_size*8
    <<value::size(value_size), rest:: bitstring>> = rest
    # Logger.info("Literal No Indexing, Indexed Name, H: #{h}, #{inspect(<<value::size(value_size)>>)}")
    {{index, value}, rest}
  end

  def literal_header_never_indexed(<<0::1, 0::1, 0::1, 1::1,
                                    0::4,
                                    _h::1,
                                    size::7,
                                    rest::bitstring>>) do # New name

    header_size = size * 8
    <<header::size(header_size), 0::1, size::7, rest::bitstring>> = rest
    value_size = size * 8
    <<value::size(value_size), rest::bitstring>> = rest
    # Logger.info("Literal, Never Indexed, H: #{h}, #{inspect(value)}")
    {{header, value}, rest}
  end
  def literal_header_never_indexed(<<0::3, 1::1,
                                    index::4,
                                    _h::1,
                                    value_size::7,
                                    rest::bitstring>>) do

    value_size = value_size * 8
    <<value::size(value_size), rest::bitstring>> = rest
    # Logger.info("Literal, Never Indexed, H: #{h}, #{inspect(value)}")
    {{index, value}, rest}
  end

  def dynamic_table_size_update(<<0::1, 0::1, 1::1, max_size::5, rest::bitstring>>) do
    # Logger.info("Dynamic table size update, max: #{max_size}")
    decode_headers(rest)
    {{:table_size_update, max_size}, rest}
  end
end
