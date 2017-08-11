defmodule Kadabra.Frame.Headers do
  @moduledoc false

  defstruct end_headers: false,
            end_stream: false,
            exclusive: nil,
            header_block_fragment: nil,
            headers: [],
            priority: false,
            stream_dependency: nil,
            stream_id: nil,
            weight: nil

  @type t :: %__MODULE__{
    end_headers: boolean,
    end_stream: boolean,
    exclusive: boolean,
    header_block_fragment: binary,
    headers: [...],
    priority: boolean,
    stream_dependency: pos_integer,
    stream_id: pos_integer,
    weight: non_neg_integer
  }

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

  def decode(%{header_block_fragment: h} = frame, context) do
    {:ok, {headers, new_context}} = :hpack.decode(h, context)
    frame = %{frame | headers: headers}
    {:ok, frame, new_context}
  end
end
