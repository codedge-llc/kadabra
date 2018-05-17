defprotocol Kadabra.Encodable do
  @moduledoc false

  @dialyzer {:nowarn_function, __protocol__: 1}
  @fallback_to_any true

  @doc ~S"""
  Encodes to binary.

  ## Examples

      iex> Kadabra.Frame.Ping.new |> to_bin()
      <<0, 0, 8, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>

      iex> %Kadabra.Connection.Settings{enable_push: false} |> to_bin()
      <<0, 5, 0, 0, 64, 0, 0, 4, 0, 0, 255, 255, 0, 1, 0, 0, 16, 0, 0, 2,
      0, 0, 0, 0>>

      iex> Kadabra.Encodable.to_bin(:any_non_frame_term)
      :error
  """
  @spec to_bin(any) :: binary | :error
  def to_bin(frame)
end

defimpl Kadabra.Encodable, for: Any do
  @doc ~S"""
  Encodes to binary.

  ## Examples

      iex> Kadabra.Encodable.to_bin(1234)
      :error
  """
  def to_bin(_), do: :error
end
