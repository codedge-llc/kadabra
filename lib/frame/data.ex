defmodule Kadabra.Frame.Data do
  defstruct [:data, end_stream: false]

  def new(%{payload: data, flags: flags}) do
    %__MODULE__{
      data: data,
      end_stream: end_stream?(flags)
    }
  end

  def end_stream?(0x1), do: true
  def end_stream?(_flags), do: false
end
