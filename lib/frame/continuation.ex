defmodule Kadabra.Frame.Continuation do
  defstruct [:header_block_fragment, end_headers: false]

  def new(%{} = frame) do
    %__MODULE__{
      header_block_fragment: frame.payload,
      end_headers: (frame.flags == 0x4)
    }
  end
end
