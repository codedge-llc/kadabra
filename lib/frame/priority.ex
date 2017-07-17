defmodule Kadabra.Frame.Priority do
  defstruct [:stream_dependency, :weight, exclusive: false]

  alias Kadabra.Frame

  @type t :: %__MODULE__{
    exclusive: boolean,
    stream_dependency: non_neg_integer,
    weight: integer
  }

  @spec new(Frame.t) :: {:ok, t} | {:error, Frame.t}
  def new(%Frame{payload: payload} = frame) do
    case parse_payload(payload) do
      {:ok, e, dep, weight} ->
        %__MODULE__{
          exclusive: (e == 0x1),
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
