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
      <<0, 1, 0, 0, 16, 0, 0, 2, 0, 0, 0, 0, 0, 4, 0, 0, 255, 255, 0, 5, 0, 0, 64, 0>>

      iex> %Kadabra.Frame.Continuation{end_headers: true,
      ...> stream_id: 1, header_block_fragment: <<255, 255, 255>>} |> to_bin()
      <<0, 0, 3, 9, 4, 0, 0, 0, 1, 255, 255, 255>>

      iex> Kadabra.Encodable.to_bin(:any_non_frame_term)
      :error
  """
  @spec to_bin(any) :: binary | :error
  def to_bin(frame)
end

defimpl Kadabra.Encodable, for: Kadabra.Frame do
  alias Kadabra.Frame

  def to_bin(%{type: type, flags: flags, stream_id: sid, payload: p}) do
    Frame.binary_frame(type, flags, sid, p)
  end
end

defimpl Kadabra.Encodable, for: Kadabra.Frame.Data do
  alias Kadabra.Frame

  @data 0x0

  def to_bin(%{end_stream: end_stream, stream_id: stream_id, data: data}) do
    flags = if end_stream, do: 0x1, else: 0x0
    Frame.binary_frame(@data, flags, stream_id, data)
  end
end

defimpl Kadabra.Encodable, for: Kadabra.Frame.Headers do
  alias Kadabra.Frame

  @headers 0x1

  def to_bin(%{header_block_fragment: block, stream_id: sid} = frame) do
    flags = flags(frame)
    Frame.binary_frame(@headers, flags, sid, block)
  end

  defp flags(%{end_headers: false, end_stream: true}), do: 0x1
  defp flags(%{end_headers: true, end_stream: false}), do: 0x4
  defp flags(%{end_headers: true, end_stream: true}), do: 0x5
end

defimpl Kadabra.Encodable, for: Kadabra.Frame.RstStream do
  alias Kadabra.Frame

  @rst_stream 0x3

  def to_bin(frame) do
    Frame.binary_frame(@rst_stream, 0x0, frame.stream_id, frame.error_code)
  end
end

defimpl Kadabra.Encodable, for: Kadabra.Frame.Settings do
  alias Kadabra.{Encodable, Frame}

  @settings 0x4

  def to_bin(frame) do
    ack = if frame.ack, do: 0x1, else: 0x0

    case frame.settings do
      nil ->
        Frame.binary_frame(@settings, ack, 0x0, <<>>)

      settings ->
        p = settings |> Encodable.to_bin()
        Frame.binary_frame(@settings, ack, 0x0, p)
    end
  end
end

defimpl Kadabra.Encodable, for: Kadabra.Frame.Ping do
  alias Kadabra.Frame

  def to_bin(frame) do
    ack = if frame.ack, do: 0x1, else: 0x0
    Frame.binary_frame(0x6, ack, 0x0, frame.data)
  end
end

defimpl Kadabra.Encodable, for: Kadabra.Frame.Goaway do
  alias Kadabra.Frame

  @goaway 0x7

  def to_bin(%{last_stream_id: id, error_code: error}) do
    payload = <<0::1, id::31>> <> error
    Frame.binary_frame(@goaway, 0x0, 0, payload)
  end
end

defimpl Kadabra.Encodable, for: Kadabra.Frame.WindowUpdate do
  alias Kadabra.Frame

  @window_update 0x8

  def to_bin(frame) do
    size = <<frame.window_size_increment::32>>
    Frame.binary_frame(@window_update, 0x0, frame.stream_id, size)
  end
end

defimpl Kadabra.Encodable, for: Kadabra.Frame.Continuation do
  alias Kadabra.Frame

  def to_bin(frame) do
    f = if frame.end_headers, do: 0x4, else: 0x0
    Frame.binary_frame(0x9, f, frame.stream_id, frame.header_block_fragment)
  end
end

defimpl Kadabra.Encodable, for: Kadabra.Connection.Settings do
  def to_bin(settings) do
    settings
    |> Map.from_struct()
    |> to_encoded_list()
    |> Enum.sort()
    |> Enum.join()
  end

  def to_encoded_list(settings) do
    Enum.reduce(settings, [], fn {k, v}, acc ->
      case v do
        nil -> acc
        :infinite -> acc
        v -> [encode_setting(k, v)] ++ acc
      end
    end)
  end

  def encode_setting(:header_table_size, v), do: <<0x1::16, v::32>>
  def encode_setting(:enable_push, true), do: <<0x2::16, 1::32>>
  def encode_setting(:enable_push, false), do: <<0x2::16, 0::32>>
  def encode_setting(:max_concurrent_streams, v), do: <<0x3::16, v::32>>
  def encode_setting(:initial_window_size, v), do: <<0x4::16, v::32>>
  def encode_setting(:max_frame_size, v), do: <<0x5::16, v::32>>
  def encode_setting(:max_header_list_size, v), do: <<0x6::16, v::32>>
end

defimpl Kadabra.Encodable, for: Any do
  def to_bin(_), do: :error
end
