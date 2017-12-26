defmodule Kadabra.Http2 do
  @moduledoc false

  require Logger

  @spec connection_preface() :: String.t()
  def connection_preface, do: "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

  @spec build_frame(integer, integer, integer, binary) :: binary
  def build_frame(frame_type, flags, stream_id, payload) do
    size = byte_size(payload)
    header = <<size::24, frame_type::8, flags::8, 0::1, stream_id::31>>
    <<header::bitstring, payload::bitstring>>
  end
end
