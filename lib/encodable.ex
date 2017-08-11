defprotocol Kadabra.Encodable do
  @moduledoc false

  @dialyzer {:nowarn_function, __protocol__: 1}
  @fallback_to_any true

  @spec to_bin(any) :: bitstring | :error
  def to_bin(frame)
end

defimpl Kadabra.Encodable, for: Any do
  def to_bin(_), do: :error
end
