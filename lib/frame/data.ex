defmodule Kadabra.Frame.Data do
  defstruct [:stream_id, :data, end_stream: false]

  alias Kadabra.Frame.Flags

  def new(%{stream_id: stream_id, payload: data, flags: flags}) do
    %__MODULE__{
      data: data,
      stream_id: stream_id,
      end_stream: Flags.end_stream?(flags)
    }
  end
end
