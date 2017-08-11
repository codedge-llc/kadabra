defmodule Kadabra.Frame.Flags do
  @moduledoc false

  use Bitwise

  @doc ~S"""
  Returns `ACK` flag.

  ## Examples

      iex> Kadabra.Frame.Flags.ack
      <<0::7, 1::1>>
  """
  def ack, do: <<0::7, 1::1>>

  @doc ~S"""
  Returns `true` if bit 0 is set to 1.

  ## Examples

      iex> Kadabra.Frame.Flags.ack?(0x1)
      true

      iex> Kadabra.Frame.Flags.ack?(0)
      false
  """
  def ack?(flags) when (flags &&& 1) == 1, do: true
  def ack?(_), do: false

  @doc ~S"""
  Returns `true` if bit 5 is set to 1.

  ## Examples

      iex> Kadabra.Frame.Flags.priority?(0x20)
      true

      iex> Kadabra.Frame.Flags.priority?(0x4)
      false
  """
  def priority?(flags) when (flags &&& 0x20) == 0x20, do: true
  def priority?(_), do: false

  @doc ~S"""
  Returns `true` if bit 3 is set to 1.

  ## Examples

      iex> Kadabra.Frame.Flags.padded?(0x8)
      true

      iex> Kadabra.Frame.Flags.padded?(0x7)
      false
  """
  def padded?(flags) when (flags &&& 8) == 8, do: true
  def padded?(_), do: false

  @doc ~S"""
  Returns `true` if bit 2 is set to 1.

  ## Examples

      iex> Kadabra.Frame.Flags.end_headers?(0x4)
      true

      iex> Kadabra.Frame.Flags.end_headers?(0x5)
      true

      iex> Kadabra.Frame.Flags.end_headers?(0x1)
      false
  """
  def end_headers?(flags) when (flags &&& 4) == 4, do: true
  def end_headers?(_), do: false

  @doc ~S"""
  Returns `true` if bit 0 is set to 1.

  ## Examples

      iex> Kadabra.Frame.Flags.end_stream?(0x1)
      true

      iex> Kadabra.Frame.Flags.end_stream?(0x0)
      false
  """
  def end_stream?(flags) when (flags &&& 1) == 1, do: true
  def end_stream?(_), do: false
end
