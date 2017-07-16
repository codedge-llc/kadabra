defmodule Kadabra.Error do
  @moduledoc """
  Handles error code conversions.
  """

  @doc ~S"""
  32-bit error code of type NO_ERROR

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
  32-bit error code of type PROTOCOL_ERROR

  The endpoint detected an unspecific protocol error. This error is for use
  when a more specific error code is not available.

  ## Examples
    
      iex> Kadabra.Error.protocol_error
      <<0, 0, 0, 1>>
  """
  @spec no_error :: <<_::32>>
  def protocol_error, do: <<1::32>>

  @doc ~S"""
  32-bit error code of type FLOW_CONTROL_ERROR

  The endpoint detected that its peer violated the flow-control protocol.

  ## Examples
    
      iex> Kadabra.Error.flow_control_error
      <<0, 0, 0, 3>>
  """
  @spec flow_control_error :: <<_::32>>
  def flow_control_error, do: <<3::32>>

  @doc ~S"""
  32-bit error code of type FRAME_SIZE_ERROR

  ## Examples
    
      iex> Kadabra.Error.frame_size_error
      <<0, 0, 0, 6>>
  """
  @spec frame_size_error :: <<_::32>>
  def frame_size_error, do: <<6::32>>

  def string(code) do
    case code do
      0x0 -> "NO_ERROR"
      0x1 -> "PROTOCOL_ERROR"
      0x2 -> "INTERNAL_ERROR"
      0x3 -> "FLOW_CONTROL_ERROR"
      0x4 -> "SETTINGS_TIMEOUT"
      0x5 -> "STREAM_CLOSED"
      0x6 -> "FRAME_SIZE_ERROR"
      0x7 -> "REFUSED_STREAM"
      0x8 -> "CANCEL"
      0x9 -> "COMPRESSION_ERROR"
      0xa -> "CONNECT_ERROR"
      0xb -> "ENHANCE_YOUR_CALM"
      0xc -> "INADEQUATE_SECURITY"
      0xd -> "HTTP_1_1_REQUIRED"
      error -> "Unknown Error: #{inspect(error)}"
    end
  end

  def code(string) do
    case string do
      "NO_ERROR"            -> 0x0
      "PROTOCOL_ERROR"      -> 0x1
      "INTERNAL_ERROR"      -> 0x2
      "FLOW_CONTROL_ERROR"  -> 0x3
      "SETTINGS_TIMEOUT"    -> 0x4
      "STREAM_CLOSED"       -> 0x5
      "FRAME_SIZE_ERROR"    -> 0x6
      "REFUSED_STREAM"      -> 0x7
      "CANCEL"              -> 0x8
      "COMPRESSION_ERROR"   -> 0x9
      "CONNECT_ERROR"       -> 0xa
      "ENHANCE_YOUR_CALM"   -> 0xb
      "INADEQUATE_SECURITY" -> 0xc
      "HTTP_1_1_REQUIRED"   -> 0xd
      error -> "Unknown Error: #{inspect(error)}"
    end
  end
end
