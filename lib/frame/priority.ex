defmodule Kadabra.Frame.Priority do
  @moduledoc false
  defstruct [:stream_dependency, :weight, exclusive: false]

  alias Kadabra.Frame

  @type t :: %__MODULE__{
    exclusive: boolean,
    stream_dependency: non_neg_integer,
    weight: integer
  }

  @doc ~S"""
  Initializes a new `Frame.Priority` from given `Frame`

  ## Examples

      iex> frame = %Kadabra.Frame{payload: <<1::1, 5::31, 0::8>>}
      iex> Kadabra.Frame.Priority.new(frame)
      %Kadabra.Frame.Priority{exclusive: true, stream_dependency: 5, weight: 1}

      iex> bad = %Kadabra.Frame{payload: <<>>}
      iex> Kadabra.Frame.Priority.new(bad)
      {:error, %Kadabra.Frame{payload: <<>>}}
  """
  @spec new(Frame.t) :: {:ok, t} | {:error, Frame.t}
  def new(%Frame{payload: payload} = frame) do
    case parse_payload(payload) do
      {:ok, e, dep, weight} ->
        %__MODULE__{
          exclusive: (e == 0x1),
          stream_dependency: dep,
          weight: weight
        }
      {:error, _payload} ->
        {:error, frame}
    end
  end

  defp parse_payload(<<e::1, dep::31, weight::8>>) do
    {:ok, e, dep, weight + 1}
  end
  defp parse_payload(payload) do
    {:error, payload}
  end
end
