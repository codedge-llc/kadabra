defmodule Kadabra.Hpack.Table do
  @moduledoc """
    Defines static table and manages dynamic table entries.
  """
  defstruct headers: [], size: 4096

  alias Kadabra.{Hpack}

  def static_header(index) do
    case index do
      1 -> {":authority", ""}
      2 -> {":method", "GET"}
      3 -> {":method", "POST"}
      4 -> {":path", "/"}
      5 -> {":path", "/index.html"}
      6 -> {":scheme", "http"}
      7 -> {":scheme", "https"}
      8 -> {":status", "200"}
      9 -> {":status", "204"}
      10 -> {":status", "206"}
      11 -> {":status", "304"}
      12 -> {":status", "400"}
      13 -> {":status", "404"}
      14 -> {":status", "500"}
      15 -> {"accept-charset", ""}
      16 -> {"accept-encoding", "gzip, deflate"}
      17 -> {"accept-language", ""}
      18 -> {"accept-ranges", ""}
      19 -> {"accept", ""}
      20 -> {"access-control-allow-origin", ""}
      21 -> {"age", ""}
      22 -> {"allow", ""}
      23 -> {"authorization", ""}
      24 -> {"cache-control", ""}
      25 -> {"content-disposition", ""}
      26 -> {"content-encoding", ""}
      27 -> {"content-language", ""}
      28 -> {"content-length", ""}
      29 -> {"content-location", ""}
      30 -> {"content-range", ""}
      31 -> {"content-type", ""}
      32 -> {"cookie", ""}
      33 -> {"date", ""}
      34 -> {"etag", ""}
      35 -> {"expect", ""}
      36 -> {"expires", ""}
      37 -> {"from", ""}
      38 -> {"host", ""}
      39 -> {"if-match", ""}
      40 -> {"if-modified-since", ""}
      41 -> {"if-none-match", ""}
      42 -> {"if-range", ""}
      43 -> {"if-unmodified-since", ""}
      44 -> {"last-modified", ""}
      45 -> {"link", ""}
      46 -> {"location", ""}
      47 -> {"max-forwards", ""}
      48 -> {"proxy-authenticate", ""}
      49 -> {"proxy-authorization", ""}
      50 -> {"range", ""}
      51 -> {"referer", ""}
      52 -> {"refresh", ""}
      53 -> {"retry-after", ""}
      54 -> {"server", ""}
      55 -> {"set-cookie", ""}
      56 -> {"strict-transport-security", ""}
      57 -> {"transfer-encoding", ""}
      58 -> {"user-agent", ""}
      59 -> {"vary", ""}
      60 -> {"via", ""}
      61 -> {"www-authenticate", ""}
      _ -> {"ERROR", index}
    end
  end

  def header(_table, index) when index < 62, do: static_header(index)
  def header(%Hpack.Table{headers: headers}, index) do
    Enum.at(headers, index - 62, index)
  end

  def add_header(%Hpack.Table{size: size} = table, header) do
    clip_size = size - entry_size(header)
    table = change_table_size(table, clip_size)
    if clip_size >= 0 do
      t = [header] ++ table.headers
      %{table | headers: t}
    else
      table
    end
  end

  def change_table_size(table, new_size) when new_size < 0 do
    %{table | headers: []}
  end
  def change_table_size(table, size) do
    headers = do_reduce_table_size(table.headers, size, 0)
    %{table | headers: headers}
  end

  defp do_reduce_table_size([], _size, _acc), do: []
  defp do_reduce_table_size(_headers, size, acc) when acc > size, do: []
  defp do_reduce_table_size(headers, size, acc) do
    [h | rest] = headers
    [h] ++ do_reduce_table_size(rest, size, acc + entry_size(h))
  end

  defp entry_size({header, value}) do
    byte_size(header) + byte_size(value) + 32
  end
end
