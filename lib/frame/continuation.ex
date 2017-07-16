defmodule Kadabra.Frame.Continuation do
  defstruct [:header_block_fragment, end_headers: false]

  alias Kadabra.Frame.Flags

  def new(%{payload: payload, flags: flags}) do
    %__MODULE__{
      header_block_fragment: payload,
      end_headers: Flags.end_headers?(flags)
    }
  end
end
