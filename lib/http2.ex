defmodule Kadabra.Http2 do
  @moduledoc """
  Handles all HTTP2 connection, request and response functions.
  """
  require Logger

  def connection_preface, do: "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

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
end
