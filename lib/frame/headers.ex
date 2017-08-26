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
  @spec new(Frame.t) :: t
  def new(%Frame{stream_id: stream_id, flags: flags, payload: p}) do
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
        weight: weight + 1,
        header_block_fragment: headers
      }
    else
      %{frame | header_block_fragment: p}
    end
  end
end
