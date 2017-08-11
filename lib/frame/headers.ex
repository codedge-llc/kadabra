defmodule Kadabra.Frame.Headers do
  @moduledoc false
  defstruct [:stream_dependency, :weight, :exclusive, :header_block_fragment,
    priority: false, end_stream: false, end_headers: false, headers: [], stream_id: nil]

  alias Kadabra.Frame.Flags

  def new(%{stream_id: stream_id, flags: flags, payload: p}) do
    frame =
      %__MODULE__{
        end_stream: Flags.end_stream?(flags),
        end_headers: Flags.end_headers?(flags),
        priority: Flags.priority?(flags),
        stream_id: stream_id
      }

    if Flags.priority?(flags) do
      <<e::1, stream_dep::31, weight::8, headers::bitstring>> = p
      %{frame |
        stream_dependency: stream_dep,
        exclusive: (e == 1),
        weight: weight,
        header_block_fragment: headers
      }
    else
      %{frame | header_block_fragment: p}
    end
  end

  def encode(frame, context) do
    {bin, new_context} = :hpack.encode(frame.headers, context)
    frame = %{frame | header_block_fragment: bin}
    {:ok, frame, new_context}
  end

  def decode(frame, context) do
    {:ok, {headers, new_context}} = :hpack.decode(frame.header_block_fragment, context)
    frame = %{frame | headers: headers}
    {:ok, frame, new_context}
  end
end
