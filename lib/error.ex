defmodule Kadabra.Error do
  def string(code) do
    case code do
      0x0 -> "NO_ERROR"
      0x1 -> "PROTOCOL_ERROR"
      0x2 -> "INTERNAL_ERROR"
      0x3 -> "FLOW_CONTROL_ERROR"
      0x4 -> "SETTINGS_TIMEOUT"
      0x5 -> "STREAM_CLOSED"
      0x6 -> "FRAME_SIZE_ERROR"
      0x7 -> "REFUSED_STREAM"
      0x8 -> "CANCEL"
      0x9 -> "COMPRESSION_ERROR"
      0xa -> "CONNECT_ERROR"
      0xb -> "ENHANCE_YOUR_CALM"
      0xc -> "INADEQUATE_SECURITY"
      0xd -> "HTTP_1_1_REQUIRED"
      error -> "Unknown Error: #{inspect(error)}"
    end
  end

  def code(string) do
    case string do
      "NO_ERROR"           -> 0x0 
      "PROTOCOL_ERROR"     -> 0x1
      "INTERNAL_ERROR"     -> 0x2
      "FLOW_CONTROL_ERROR" -> 0x3
      "SETTINGS_TIMEOUT"   -> 0x4
      "STREAM_CLOSED"      -> 0x5
      "FRAME_SIZE_ERROR"   -> 0x6
      "REFUSED_STREAM"     -> 0x7
      "CANCEL"             -> 0x8
      "COMPRESSION_ERROR"  -> 0x9
      "CONNECT_ERROR"      -> 0xa
      "ENHANCE_YOUR_CALM"  -> 0xb
      "INADEQUATE_SECURITY" -> 0xc
      "HTTP_1_1_REQUIRED"  -> 0xd
      error -> "Unknown Error: #{inspect(error)}"
    end
  end
end
