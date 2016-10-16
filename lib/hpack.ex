defmodule Kadabra.Hpack do
  @moduledoc """
    Decodes headers as specified in RFC 7451.
  """
  defstruct dynamic_table: []
  require Logger

  alias Kadabra.{Hpack, Huffman}

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
  defp decode_value(1, size, value) do
    <<value::size(size)>>
    |> Huffman.decode
    |> List.to_string
  end

  def indexed_header(<<1::1, index::7, rest::bitstring>>, table), do:
    {Hpack.Table.header(table, index), <<rest::bitstring>>, table}

  def literal_header_inc_indexing(<<0::1, 1::1,
                                    0::6,
                                    h::1,
                                    name_size::7,
                                    rest::bitstring>>, table) do # New name

    name_size = name_size * 8
    <<name::size(name_size), rest::bitstring>> = rest
    name_string = decode_value(h, name_size, name)

    <<h_2::1, value_size::7, rest::bitstring>> = rest
    value_size = value_size * 8
    <<value::size(value_size), rest::bitstring>> = rest
    value_string = decode_value(h_2, value_size, value)

    table = Hpack.Table.add_header(table, {name_string, value_string})

    IO.puts """
      Literal, Inc Indexing New Name
      H: #{h}
      H2: #{h_2}
      Name: #{name_string}
      Value: #{value_string}
    """
    {{name_string, value_string}, rest, table}
  end
  def literal_header_inc_indexing(<<0::1, 1::1,
                                    index::6,
                                    rest::bitstring>>, table) do

    {index, rest} = Hpack.Integer.decode(<<index::6, rest::bitstring>>, 6)
    IO.puts("Literal, Inc Indexing, #{inspect(index)}")

    {header, _} = Hpack.Table.header(table, index)

    <<h::1, value_size::7, rest::bitstring>> = rest
    value_size = value_size * 8
    <<value::size(value_size), rest::bitstring>> = rest
    value_string = decode_value(h, value_size, value)

    table = Hpack.Table.add_header(table, {header, value_string})

    IO.puts("Literal, Inc Indexing, H: #{h}, Name: #{header}, Value: #{value_string}")
    {{header, value_string}, <<rest::bitstring>>, table}
  end

  def literal_header_no_indexing(<<0::4,
                                   0::4,
                                   h::1,
                                   name_size::7,
                                   rest::bitstring>>, table) do # New name

    name_size = name_size * 8
    <<name::size(name_size), rest::bitstring>> = rest
    name_string = decode_value(h, name_size, name)

    <<h_2::1, value_size::7, rest::bitstring>> = rest
    value_size = value_size * 8
    <<value::size(value_size), rest::bitstring>> = rest
    value_string = decode_value(h_2, value_size, value)

    {{name_string, value_string}, rest, table}
  end
  def literal_header_no_indexing(<<0::4,
                                   index::4,
                                   rest::bitstring>>, table) do

    {index, rest} = Hpack.Integer.decode(<<index::4, rest::bitstring>>, 4)
    {header, _} = Hpack.Table.header(table, index)

    <<h::1, value_size::7, rest::bitstring>> = rest
    value_size = value_size * 8
    <<value::size(value_size), rest::bitstring>> = rest
    value_string = decode_value(h, value_size, value)

    {{header, value_string}, rest, table}
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

    {{header_string, value_string}, rest, table}
  end
  def literal_header_never_indexed(<<0::3, 1::1,
                                     index::4,
                                     rest::bitstring>>, table) do

    {index, rest} = Hpack.Integer.decode(<<index::4, rest::bitstring>>, 4)
    {header, _} = Hpack.Table.header(table, index)

    <<h::1, value_size::7, rest::bitstring>> = rest
    value_size = value_size * 8
    <<value::size(value_size), rest::bitstring>> = rest
    value_string = decode_value(h, value_size, value)

    {{header, value_string}, rest, table}
  end

  def dynamic_table_size_update(<<0::1, 0::1, 1::1, prefix::5, rest::bitstring>>, table) do
    {value, rest} = Hpack.Integer.decode(<<prefix::5, rest::bitstring>>, 5)
    table = Hpack.Table.change_table_size(table, value)
    table = %Hpack.Table{table | size: value}
    {[], rest, table}
  end
end
