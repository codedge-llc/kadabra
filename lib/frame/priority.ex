defmodule Kadabra.Frame.Priority do
  defstruct [:stream_dependency, :weight, exclusive: false]

  def new(%{} = frame) do
    case parse_payload(frame.payload) do
      {:ok, e, dep, weight} ->
        %__MODULE__{
          exclusive: (e == 1),
          stream_dependency: dep,
          weight: weight 
        }
      {:error, payload} ->
        {:error, frame}
    end
  end

  defp parse_payload(<<e::1, dep::31, weight::8>>) do
    {:ok, e, dep, weight}
  end
  defp parse_payload(payload) do
    {:error, payload}
  end
end
