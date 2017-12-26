defmodule Kadabra.Frame.Continuation do
  @moduledoc false

  defstruct [:header_block_fragment, :stream_id, end_headers: false]

  @type t :: %__MODULE__{
          end_headers: boolean,
          header_block_fragment: bitstring,
          stream_id: pos_integer
        }

  alias Kadabra.Frame.Flags

  @doc ~S"""
  Initializes a new `Frame.Continuation` given a `Frame`.

  ## Examples

      iex> frame = %Kadabra.Frame{payload: <<136>>, flags: 0x4}
      iex> Kadabra.Frame.Continuation.new(frame)
      %Kadabra.Frame.Continuation{header_block_fragment: <<136>>,
      end_headers: true}
  """
  @spec new(Kadabra.Frame.t()) :: t
  def new(%{stream_id: id, payload: payload, flags: flags}) do
    %__MODULE__{
      header_block_fragment: payload,
      end_headers: Flags.end_headers?(flags),
      stream_id: id
    }
  end
end
