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
      28 -> "content-length"
      31 -> "content-type"
      32 -> "cookie"
      33 -> "date"
      34 -> "etag"
      35 -> "expect"
      36 -> "expires"
      37 -> "from"
      38 -> "host"
      39 -> "if-match"
      40 -> "if-modified-since"
      46 -> "location"
      _ -> index
    end
  end
end
