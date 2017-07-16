defmodule Kadabra.Frame.WindowUpdate do
  defstruct [:stream_id, :window_size_increment]

  def new(%{payload: p, stream_id: stream_id}) do
    %__MODULE__{
      window_size_increment: p,
      stream_id: stream_id
    }
  end
end
