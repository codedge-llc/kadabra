defmodule Kadabra.Frame.Flags do

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

      iex> Kadabra.Frame.Flags.ack?(<<0::7, 1::1>>)
      true
      iex> Kadabra.Frame.Flags.ack?(0x1)
      true

      iex> Kadabra.Frame.Flags.ack?(<<0::8>>)
      false
      iex> Kadabra.Frame.Flags.ack?(0)
      false
  """
  def ack?(<<_::7, 1::1>>), do: true
  def ack?(0x1), do: true
  def ack?(_ack), do: false

  @doc ~S"""
  Returns `true` if bit 5 is set to 1.

  ## Examples

      iex> Kadabra.Frame.Flags.priority?(<<0::2, 1::1, 0::5>>)
      true

      iex> Kadabra.Frame.Flags.priority?(<<0::8>>)
      false
  """
  def priority?(<<_::2, 1::1, _::5>>), do: true
  def priority?(_), do: false

  @doc ~S"""
  Returns `true` if bit 3 is set to 1.

  ## Examples

      iex> Kadabra.Frame.Flags.padded?(<<0::5, 1::1, 0::2>>)
      true

      iex> Kadabra.Frame.Flags.padded?(<<0::8>>)
      false
  """
  def padded?(<<_::5, 1::1, _::2>>), do: true
  def padded?(_), do: false

  @doc ~S"""
  Returns `true` if bit 2 is set to 1.

  ## Examples

      iex> Kadabra.Frame.Flags.end_headers?(<<0::6, 1::1, 0::1>>)
      true

      iex> Kadabra.Frame.Flags.end_headers?(<<0::8>>)
      false
  """
  def end_headers?(<<_::6, 1::1, _::1>>), do: true
  def end_headers?(_), do: false

  @doc ~S"""
  Returns `true` if bit 0 is set to 1.

  ## Examples

      iex> Kadabra.Frame.Flags.end_stream?(<<0::7, 1::1>>)
      true

      iex> Kadabra.Frame.Flags.end_stream?(<<0::8>>)
      false
  """
  def end_stream?(<<_::7, 1::1>>), do: true
  def end_stream?(0x1), do: true
  def end_stream?(_), do: false
end
