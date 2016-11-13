defmodule Kadabra.Hpack.Integer do
  @moduledoc """
    Hpack integer decoding.
  """
  require Logger

  def decode(<<1::1, bin::bitstring>>, 1), do: prefix_add(1, decode(bin, 0, 0))
  def decode(<<3::2, bin::bitstring>>, 2), do: prefix_add(3, decode(bin, 0, 0))
  def decode(<<7::3, bin::bitstring>>, 3), do: prefix_add(7, decode(bin, 0, 0))
  def decode(<<15::4, bin::bitstring>>, 4), do: prefix_add(15, decode(bin, 0, 0))
  def decode(<<31::5, bin::bitstring>>, 5), do: prefix_add(31, decode(bin, 0, 0))
  def decode(<<63::6, bin::bitstring>>, 6), do: prefix_add(63, decode(bin, 0, 0))
  def decode(<<127::7, bin::bitstring>>, 7), do: prefix_add(127, decode(bin, 0, 0))
  def decode(<<255::8, bin::bitstring>>, 8), do: prefix_add(255, decode(bin, 0, 0))
  def decode(bin, bits) do
    <<value::size(bits), rest::bitstring>> = bin
    {value, rest}
  end

  def decode(<<1::1, int::7, rest::bitstring>>, m, i) do
    decode(rest, m + 7, round(i + int * :math.pow(2, m)))
  end
  def decode(<<0::1, int::7, rest::bitstring>>, m, i) do
    {round(i + int * :math.pow(2, m)), <<rest::bitstring>>}
  end

  def prefix_add(bits, {i, rest}), do: {bits + i, rest}
end
