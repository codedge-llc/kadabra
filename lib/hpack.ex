defmodule Kadabra.Hpack do
  defstruct dynamic_table: []
  require Logger

  alias Kadabra.{Hpack, Huffman}

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

  def header(index, table) when index < 62, do: static_header(index)
  def header(index, %Hpack{dynamic_table: table}) do
    #IO.puts("Fetching index #{index - 62 - 2}")
    IO.inspect table
    Enum.at(table, index - 62 - 2, index)
    #|> IO.inspect
  end

  def decode_headers(bin, table), do: do_decode_headers(bin, [], table)

  def do_decode_headers(<<>>, headers, table), do: {headers, table}
  def do_decode_headers(bin, headers, table) do
    {header, rest, table} =
      case bin do
        <<1::1, _rest::bitstring>> -> indexed_header(bin, table)
        <<0::1, 1::1, _rest::bitstring>> -> literal_header_inc_indexing(bin, table)
        <<0::4, _rest::bitstring>> -> literal_header_no_indexing(bin, table)
        <<0::3, 1::1, _rest::bitstring>> -> literal_header_never_indexed(bin, table)
        <<0::2, 1::1, _rest::bitstring>> -> dynamic_table_size_update(bin, table)
      end
    do_decode_headers(rest, headers ++ [header], table)
  end

  defp decode_value(0, _size, value), do: value
  defp decode_value(1, size, value), do: <<value::size(size)>> |> Huffman.decode |> List.to_string

  def indexed_header(<<1::1, index::7, rest::bitstring>>, table), do: {header(index, table), <<rest::bitstring>>, table}

  def literal_header_inc_indexing(<<0::1, 1::1, 0::6, h::1, name_size::7, rest::bitstring>>, table) do # New name
    name_size = name_size * 8
    <<name::size(name_size), rest::bitstring>> = rest
    name_string = decode_value(h, name_size, name)

    <<h_2::1, value_size::7, rest::bitstring>> = rest
    value_size = value_size * 8
    <<value::size(value_size), rest::bitstring>> = rest
    value_string = decode_value(h_2, value_size, value)

    t = [{name_string, value_string}] ++ table.dynamic_table
    table = %{table | dynamic_table: t}

    IO.puts("Literal, Inc Indexing New Name, H: #{h}, H2: #{h_2}, Name: #{name_string}, Value: #{value_string}")
    {{name_string, value_string}, rest, table}
  end
  def literal_header_inc_indexing(<<0::1, 1::1, index::6, rest::bitstring>> = full_bin, table) do
    case Hpack.Integer.decode(<<index::6, rest::bitstring>>, 6) do
      {index, rest} ->
        IO.puts("Literal, Inc Indexing, #{inspect(index)}")

        {header, _} = header(index, table)

        <<h::1, value_size::7, rest::bitstring>> = rest
        value_size = value_size*8
        <<value::size(value_size), rest::bitstring>> = rest
        value_string = decode_value(h, value_size, value)

        t = [{header, value_string}] ++ table.dynamic_table
        table = %{table | dynamic_table: t}

        IO.puts("Literal, Inc Indexing, H: #{h}, Name: #{header}, Value: #{value_string}")
        {{header, value_string}, <<rest::bitstring>>, table}
      bin -> Logger.error(inspect(bin))
    end
  end

  def literal_header_no_indexing(<<0::4, 0::4, h::1, name_size::7, rest::bitstring>>, table) do # New name
    name_size = name_size * 8
    <<name::size(name_size), rest::bitstring>> = rest
    name_string = decode_value(h, name_size, name)

    <<h_2::1, value_size::7, rest::bitstring>> = rest
    value_size = value_size * 8
    <<value::size(value_size), rest::bitstring>> = rest
    value_string = decode_value(h_2, value_size, value)

    Logger.info("Literal No Indexing, New Name, Header: #{name_string}, Value: #{value_string}")
    {{name_string, value_string}, rest, table}
  end
  def literal_header_no_indexing(<<0::4, index::4, rest::bitstring>> = full_bin, table) do
    Logger.info """

      Literal No Indexing
      #{inspect(<<index::4>>)}
      #{inspect(rest)}
      """

    case Hpack.Integer.decode(<<index::4, rest::bitstring>>, 4) do
      {index, rest} ->
        Logger.info "Index: #{index}, Rest: #{inspect(rest)}"
        {header, _} = header(index, table)

        <<h::1, value_size::7, rest::bitstring>> = rest
        value_size = value_size*8
        <<value::size(value_size), rest::bitstring>> = rest
        value_string = decode_value(h, value_size, value)

        {{header, value_string}, rest, table}
    end
  end

  def literal_header_never_indexed(<<0::3, 1::1,
                                    0::4,
                                    h::1,
                                    size::7,
                                    rest::bitstring>>, table) do # New name

    header_size = size * 8
    <<header::size(header_size), h_2::1, size::7, rest::bitstring>> = rest
    header_string = decode_value(h, header_size, header)

    value_size = size * 8
    <<value::size(value_size), rest::bitstring>> = rest
    value_string = decode_value(h_2, value_size, value)

    Logger.info("Literal, Never Indexed, H: #{h}, #{inspect(value)}")
    {{header_string, value_string}, rest, table}
  end
  def literal_header_never_indexed(<<0::3, 1::1, index::4, rest::bitstring>> = full_bin, table) do
    Logger.info """

      Literal Never Indexed
      #{inspect(<<index::4>>)}
      #{inspect(rest)}
      """
    case Hpack.Integer.decode(<<index::4, rest::bitstring>>, 4) do
      {index, rest} ->
        Logger.info "Index: #{index}, Rest: #{inspect(rest)}"
        {header, _} = header(index, table)

        <<h::1, value_size::7, rest::bitstring>> = rest
        value_size = value_size*8
        <<value::size(value_size), rest::bitstring>> = rest
        value_string = decode_value(h, value_size, value)

        {{header, value_string}, rest, table}
    end
  end

  def dynamic_table_size_update(<<0::1, 0::1, 1::1, max_size::5, rest::bitstring>>, table) do
    Logger.info("Dynamic table size update, max: #{max_size}")
    #decode_headers(rest)
    {{:table_size_update, max_size}, rest, table}
  end
end
