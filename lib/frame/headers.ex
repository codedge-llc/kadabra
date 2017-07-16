defmodule Kadabra.Frame.Headers do
  defstruct [:stream_dependency, :weight, :exclusive, :header_block_fragment,
    priority: false, end_stream: false, end_headers: false]

  def new(%{flags: flags, payload: p}) do
    frame =
      %__MODULE__{
        end_stream: end_stream?(flags),
        end_headers: end_headers?(flags),
        priority: priority?(flags)
      }

    if priority?(flags) do
      <<e::1, stream_dep::31, weight::8, headers::bitstring>> = p
      %{frame |
        stream_dependency: stream_dep,
        exclusive: (e == 1),
        weight: weight,
        header_block_fragment: headers
      }
    else
      %{frame | header_block_fragment: p}
    end
  end

  @doc ~S"""
  Returns `true` if bit 5 is set to 1.

  ## Examples

      iex> Kadabra.Frame.Headers.priority?(<<0::2, 1::1, 0::5>>)
      true

      iex> Kadabra.Frame.Headers.priority?(<<0::8>>)
      false
  """
  def priority?(<<_::2, 1::1, _::5>>), do: true
  def priority?(_), do: false

  @doc ~S"""
  Returns `true` if bit 3 is set to 1.

  ## Examples

      iex> Kadabra.Frame.Headers.padded?(<<0::5, 1::1, 0::2>>)
      true

      iex> Kadabra.Frame.Headers.padded?(<<0::8>>)
      false
  """
  def padded?(<<_::5, 1::1, _::2>>), do: true
  def padded?(_), do: false

  @doc ~S"""
  Returns `true` if bit 2 is set to 1.

  ## Examples

      iex> Kadabra.Frame.Headers.end_headers?(<<0::6, 1::1, 0::1>>)
      true

      iex> Kadabra.Frame.Headers.end_headers?(<<0::8>>)
      false
  """
  def end_headers?(<<_::6, 1::1, _::1>>), do: true
  def end_headers?(_), do: false

  @doc ~S"""
  Returns `true` if bit 0 is set to 1.

  ## Examples

      iex> Kadabra.Frame.Headers.end_stream?(<<0::7, 1::1>>)
      true

      iex> Kadabra.Frame.Headers.end_stream?(<<0::8>>)
      false
  """
  def end_stream?(<<_::7, 1::1>>), do: true
  def end_stream?(_), do: false
end
