defmodule Kadabra.Frame.Headers do
  @moduledoc false

  defstruct end_headers: false,
            end_stream: false,
            exclusive: nil,
            header_block_fragment: nil,
            priority: false,
            stream_dependency: nil,
            stream_id: nil,
            weight: nil

  @type t :: %__MODULE__{
          end_headers: boolean,
          end_stream: boolean,
          exclusive: boolean,
          header_block_fragment: binary,
          priority: boolean,
          stream_dependency: pos_integer,
          stream_id: pos_integer,
          weight: non_neg_integer
        }

  alias Kadabra.Frame
  alias Kadabra.Frame.Flags

  @doc ~S"""
  Initializes a new `Frame.Headers` from given `Frame`.

  ## Examples

      iex> frame = %Kadabra.Frame{stream_id: 1, flags: 0x5, payload: <<136>>}
      iex> Kadabra.Frame.Headers.new(frame)
      %Kadabra.Frame.Headers{stream_id: 1, end_stream: true, end_headers: true,
      priority: false, header_block_fragment: <<136>>, weight: nil,
      exclusive: nil, stream_dependency: nil}

      iex> frame = %Kadabra.Frame{stream_id: 3, flags: 0x25,
      ...> payload: <<1::1, 1::31, 2::8, 136::8>>}
      iex> Kadabra.Frame.Headers.new(frame)
      %Kadabra.Frame.Headers{stream_id: 3, end_stream: true,
      end_headers: true, priority: true, header_block_fragment: <<136>>,
      weight: 3, exclusive: true, stream_dependency: 1}
  """
  @spec new(Frame.t()) :: t
  def new(%Frame{stream_id: stream_id, flags: flags, payload: p}) do
    frame =
      %__MODULE__{}
      |> put_flags(flags)
      |> Map.put(:stream_id, stream_id)

    if Flags.priority?(flags) do
      put_priority(frame, p)
    else
      Map.put(frame, :header_block_fragment, p)
    end
  end

  defp put_flags(frame, flags) do
    frame
    |> Map.put(:end_stream, Flags.end_stream?(flags))
    |> Map.put(:end_headers, Flags.end_headers?(flags))
    |> Map.put(:priority, Flags.priority?(flags))
  end

  defp put_priority(frame, payload) do
    <<e::1, stream_dep::31, weight::8, headers::bitstring>> = payload

    frame
    |> Map.put(:stream_dependency, stream_dep)
    |> Map.put(:exclusive, e == 1)
    |> Map.put(:weight, weight + 1)
    |> Map.put(:header_block_fragment, headers)
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
