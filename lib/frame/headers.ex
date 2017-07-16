defmodule Kadabra.Frame.Headers do
  defstruct [:stream_dependency, :weight, :exclusive, :header_block_fragment,
    priority: false, end_stream: false, end_headers: false]

  alias Kadabra.Frame.Flags

  def new(%{flags: flags, payload: p}) do
    frame =
      %__MODULE__{
        end_stream: Flags.end_stream?(flags),
        end_headers: Flags.end_headers?(flags),
        priority: Flags.priority?(flags)
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
end
