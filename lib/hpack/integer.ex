defmodule Kadabra.Hpack.Integer do
  @moduledoc """
    Hpack integer decoding.
  """
  require Logger

  def decode(<<15::4, bin::bitstring>>, _bits), do: prefix_add(15, decode(bin, 0, 0))
  def decode(<<31::5, bin::bitstring>>, _bits), do: prefix_add(31, decode(bin, 0, 0))
  def decode(<<63::6, bin::bitstring>>, _bits), do: prefix_add(63, decode(bin, 0, 0))
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
