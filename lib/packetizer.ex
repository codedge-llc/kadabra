defmodule Kadabra.Packetizer do
  alias Kadabra.Frame

  def headers(stream_id, headers_payload, max_size, end_stream?) do
    headers([], stream_id, headers_payload, max_size, end_stream?)
  end

  def headers(frames, _stream_id, <<>>, _max_size, _end_stream?) do
    frames
  end

  def headers([], stream_id, headers_payload, max_size, end_stream?)
      when byte_size(headers_payload) <= max_size do
    [
      %Frame.Headers{
        stream_id: stream_id,
        header_block_fragment: headers_payload,
        end_stream: end_stream?,
        end_headers: true
      }
    ]
  end

  def headers([], stream_id, headers_payload, max_size, end_stream?) do
    {chunk, rest} = :erlang.split_binary(headers_payload, max_size)

    frame = %Frame.Headers{
      stream_id: stream_id,
      header_block_fragment: chunk,
      end_stream: end_stream?,
      end_headers: false
    }

    headers([frame], stream_id, rest, max_size, end_stream?)
  end

  def headers(frames, stream_id, headers_payload, max_size, _end_stream?)
      when byte_size(headers_payload) <= max_size do
    frame = %Frame.Continuation{
      stream_id: stream_id,
      header_block_fragment: headers_payload,
      end_headers: true
    }

    frames ++ [frame]
  end

  def headers(frames, stream_id, headers_payload, max_size, end_stream?) do
    # IO.inspect(frames)
    {chunk, rest} = :erlang.split_binary(headers_payload, max_size)

    frame = %Frame.Continuation{
      stream_id: stream_id,
      header_block_fragment: chunk,
      end_headers: rest == <<>>
    }

    headers(frames ++ [frame], stream_id, rest, max_size, end_stream?)
  end

  def split(size, p) when byte_size(p) >= size do
    {chunk, rest} = :erlang.split_binary(p, size)
    [chunk | split(size, rest)]
  end

  def split(_size, <<>>), do: []
  def split(_size, p), do: [p]
end
