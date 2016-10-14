defmodule Kadabra.Hpack.Integer do
  require Logger
  alias Kadabra.Huffman

  def decode(<<15::4, bin::bitstring>>, bits) do
    IO.puts("Prefix 1111")
    prefix_add(15, decode(bin, 0, 0))
  end
  def decode(<<63::6, bin::bitstring>>, bits) do
    IO.puts("Prefix 1111111")
    prefix_add(63, decode(bin, 0, 0))
  end
  def decode(bin, bits) do
    <<value::size(bits), rest::bitstring>> = bin
    IO.puts("Prefix #{inspect(<<value::size(bits)>>)}")
    {value, rest}
  end

  def decode(<<1::1, int::7, rest::bitstring>>, m, i) do
    decode(rest, m + 7, round(i + int * :math.pow(2, m)))
  end
  def decode(<<0::1, int::7, rest::bitstring>>, m, i) do
    {round(i + int * :math.pow(2, m)), <<rest::bitstring>>}
  end

  def prefix_add(bits, {i, rest}) do
    {bits + i, rest}
  end
end
