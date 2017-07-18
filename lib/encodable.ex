defprotocol Kadabra.Encodable do
  @doc ~S"""
  Packs frame into sendable frame with frame header.
  """
  def to_bin(frame)
end
