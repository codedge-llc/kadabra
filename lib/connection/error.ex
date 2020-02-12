defmodule Kadabra.Connection.Error do
  @moduledoc false

  @type error ::
          :NO_ERROR
          | :PROTOCOL_ERROR
          | :INTERNAL_ERROR
          | :FLOW_CONTROL_ERROR
          | :SETTINGS_TIMEOUT
          | :STREAM_CLOSED
          | :FRAME_SIZE_ERROR
          | :REFUSED_STREAM
          | :CANCEL
          | :COMPRESSION_ERROR
          | :CONNECT_ERROR
          | :ENHANCE_YOUR_CALM
          | :INADEQUATE_SECURITY
          | :HTTP_1_1_REQUIRED

  @doc ~S"""
  32-bit error code of type `NO_ERROR`

  The associated condition is not a result of an error. For example,
  a GOAWAY might include this code to indicate graceful shutdown of
  a connection.

  ## Examples

      iex> Kadabra.Connection.Error.no_error
      <<0, 0, 0, 0>>
  """
  @spec no_error :: <<_::32>>
  def no_error, do: <<0::32>>

  @doc ~S"""
  32-bit error code of type `PROTOCOL_ERROR`

  The endpoint detected an unspecific protocol error. This error is for use
  when a more specific error code is not available.

  ## Examples

      iex> Kadabra.Connection.Error.protocol_error
      <<0, 0, 0, 1>>
  """
  @spec protocol_error :: <<_::32>>
  def protocol_error, do: <<1::32>>

  @doc ~S"""
  32-bit error code of type `FLOW_CONTROL_ERROR`

  The endpoint detected that its peer violated the flow-control protocol.

  ## Examples

      iex> Kadabra.Connection.Error.flow_control_error
      <<0, 0, 0, 3>>
  """
  @spec flow_control_error :: <<_::32>>
  def flow_control_error, do: <<3::32>>

  @doc ~S"""
  32-bit error code of type `FRAME_SIZE_ERROR`

  ## Examples

      iex> Kadabra.Connection.Error.frame_size_error
      <<0, 0, 0, 6>>
  """
  @spec frame_size_error :: <<_::32>>
  def frame_size_error, do: <<6::32>>

  @doc ~S"""
  32-bit error code of type `COMPRESSION_ERROR`

  ## Examples

      iex> Kadabra.Connection.Error.compression_error
      <<0, 0, 0, 9>>
  """
  @spec compression_error :: <<_::32>>
  def compression_error, do: <<9::32>>

  @doc ~S"""
  Returns a string error given integer error in range 0x0 - 0xd.

  ## Examples

      iex> Kadabra.Connection.Error.parse(0x1)
      :PROTOCOL_ERROR
      iex> Kadabra.Connection.Error.parse(0xfff)
      0xfff
  """
  @spec parse(integer) :: error | integer
  def parse(0x0), do: :NO_ERROR
  def parse(0x1), do: :PROTOCOL_ERROR
  def parse(0x2), do: :INTERNAL_ERROR
  def parse(0x3), do: :FLOW_CONTROL_ERROR
  def parse(0x4), do: :SETTINGS_TIMEOUT
  def parse(0x5), do: :STREAM_CLOSED
  def parse(0x6), do: :FRAME_SIZE_ERROR
  def parse(0x7), do: :REFUSED_STREAM
  def parse(0x8), do: :CANCEL
  def parse(0x9), do: :COMPRESSION_ERROR
  def parse(0xA), do: :CONNECT_ERROR
  def parse(0xB), do: :ENHANCE_YOUR_CALM
  def parse(0xC), do: :INADEQUATE_SECURITY
  def parse(0xD), do: :HTTP_1_1_REQUIRED
  def parse(error), do: error

  @doc ~S"""
  Returns integer error code given string error.

  ## Examples

      iex> Kadabra.Connection.Error.code(:PROTOCOL_ERROR)
      0x1
      iex> Kadabra.Connection.Error.code(:NOT_AN_ERROR)
      :NOT_AN_ERROR
  """
  @spec code(error) :: integer
  def code(:NO_ERROR), do: 0x0
  def code(:PROTOCOL_ERROR), do: 0x1
  def code(:INTERNAL_ERROR), do: 0x2
  def code(:FLOW_CONTROL_ERROR), do: 0x3
  def code(:SETTINGS_TIMEOUT), do: 0x4
  def code(:STREAM_CLOSED), do: 0x5
  def code(:FRAME_SIZE_ERROR), do: 0x6
  def code(:REFUSED_STREAM), do: 0x7
  def code(:CANCEL), do: 0x8
  def code(:COMPRESSION_ERROR), do: 0x9
  def code(:CONNECT_ERROR), do: 0xA
  def code(:ENHANCE_YOUR_CALM), do: 0xB
  def code(:INADEQUATE_SECURITY), do: 0xC
  def code(:HTTP_1_1_REQUIRED), do: 0xD
  def code(error), do: error
end
