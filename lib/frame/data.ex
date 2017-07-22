defmodule Kadabra.Frame.Data do
  defstruct [:data, end_stream: false]

  alias Kadabra.Frame.Flags

  def new(%{payload: data, flags: flags}) do
    %__MODULE__{
      data: data,
      end_stream: Flags.end_stream?(flags)
    }
  end
end
