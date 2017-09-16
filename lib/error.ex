defmodule Kadabra.Error do
  @moduledoc false

  @doc ~S"""
  32-bit error code of type `NO_ERROR`

  The associated condition is not a result of an error. For example,
  a GOAWAY might include this code to indicate graceful shutdown of
  a connection.

  ## Examples

      iex> Kadabra.Error.no_error
      <<0, 0, 0, 0>>
  """
  @spec no_error :: <<_::32>>
  def no_error, do: <<0::32>>

  @doc ~S"""
  32-bit error code of type `PROTOCOL_ERROR`

  The endpoint detected an unspecific protocol error. This error is for use
  when a more specific error code is not available.

  ## Examples

      iex> Kadabra.Error.protocol_error
      <<0, 0, 0, 1>>
  """
  @spec protocol_error :: <<_::32>>
  def protocol_error, do: <<1::32>>

  @doc ~S"""
  32-bit error code of type `FLOW_CONTROL_ERROR`

  The endpoint detected that its peer violated the flow-control protocol.

  ## Examples

      iex> Kadabra.Error.flow_control_error
      <<0, 0, 0, 3>>
  """
  @spec flow_control_error :: <<_::32>>
  def flow_control_error, do: <<3::32>>

  @doc ~S"""
  32-bit error code of type `FRAME_SIZE_ERROR`

  ## Examples

      iex> Kadabra.Error.frame_size_error
      <<0, 0, 0, 6>>
  """
  @spec frame_size_error :: <<_::32>>
  def frame_size_error, do: <<6::32>>

  @doc ~S"""
  Returns a string error given integer error in range 0x0 - 0xd.

  ## Examples

      iex> Kadabra.Error.string(0x1)
      "PROTOCOL_ERROR"
      iex> Kadabra.Error.string(0xfff)
      0xfff
  """
  @spec string(integer) :: String.t | integer
  def string(0x0), do: "NO_ERROR"
  def string(0x1), do: "PROTOCOL_ERROR"
  def string(0x2), do: "INTERNAL_ERROR"
  def string(0x3), do: "FLOW_CONTROL_ERROR"
  def string(0x4), do: "SETTINGS_TIMEOUT"
  def string(0x5), do: "STREAM_CLOSED"
  def string(0x6), do: "FRAME_SIZE_ERROR"
  def string(0x7), do: "REFUSED_STREAM"
  def string(0x8), do: "CANCEL"
  def string(0x9), do: "COMPRESSION_ERROR"
  def string(0xa), do: "CONNECT_ERROR"
  def string(0xb), do: "ENHANCE_YOUR_CALM"
  def string(0xc), do: "INADEQUATE_SECURITY"
  def string(0xd), do: "HTTP_1_1_REQUIRED"
  def string(error), do: error

  @doc ~S"""
  Returns integer error code given string error.

  ## Examples

      iex> Kadabra.Error.code("PROTOCOL_ERROR")
      0x1
      iex> Kadabra.Error.code("NOT_AN_ERROR")
      "NOT_AN_ERROR"
  """
  def code("NO_ERROR"), do: 0x0
  def code("PROTOCOL_ERROR"), do: 0x1
  def code("INTERNAL_ERROR"), do: 0x2
  def code("FLOW_CONTROL_ERROR"), do: 0x3
  def code("SETTINGS_TIMEOUT"), do: 0x4
  def code("STREAM_CLOSED"), do: 0x5
  def code("FRAME_SIZE_ERROR"), do: 0x6
  def code("REFUSED_STREAM"), do: 0x7
  def code("CANCEL"), do: 0x8
  def code("COMPRESSION_ERROR"), do: 0x9
  def code("CONNECT_ERROR"), do: 0xa
  def code("ENHANCE_YOUR_CALM"), do: 0xb
  def code("INADEQUATE_SECURITY"), do: 0xc
  def code("HTTP_1_1_REQUIRED"), do: 0xd
  def code(error), do: error
end
