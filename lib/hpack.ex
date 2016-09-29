defmodule Kadabra.Hpack do
  def static_header(index) do
    case index do
      1 -> ":authority"
      2 -> {":method", "GET"}
      3 -> {":method", "POST"}
      4 -> {":path", "/"}
      5 -> {":path", "/index.html"}
      6 -> {":scheme", "http"}
      7 -> {":scheme", "https"}
      8 -> {":status", "200"}
      26 -> "content-encoding"
      36 -> "expires"
      37 -> "from"
      46 -> "location"
      _ -> index
    end
  end
end
