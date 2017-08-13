defprotocol Kadabra.Encodable do
  @moduledoc false

  @dialyzer {:nowarn_function, __protocol__: 1}
  @fallback_to_any true

  @doc ~S"""
  Encodes to binary.

  ## Examples

      iex> Kadabra.Frame.Ping.new |> Kadabra.Encodable.to_bin
      <<0, 0, 8, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>

      iex> Kadabra.Encodable.to_bin(:any_non_frame_term)
      :error
  """
  @spec to_bin(any) :: bitstring | :error
  def to_bin(frame)
end

defimpl Kadabra.Encodable, for: Any do
  def to_bin(_), do: :error
end
