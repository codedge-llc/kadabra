defprotocol Kadabra.Encodable do
  @doc ~S"""
  Packs frame into sendable frame with frame header.
  """

  @dialyzer {:nowarn_function, __protocol__: 1}
  @fallback_to_any true

  @spec to_bin(any) :: bitstring | :error
  def to_bin(frame)
end

defimpl Kadabra.Encodable, for: Any do
  def to_bin(_), do: :error
end
