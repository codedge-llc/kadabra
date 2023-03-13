defmodule Kadabra.Frame.Data do
  @moduledoc false

  defstruct [:stream_id, :data, end_stream: false]

  import Bitwise

  alias Kadabra.Frame

  @type t :: %__MODULE__{
          data: binary,
          end_stream: boolean,
          stream_id: pos_integer
        }

  @spec new(Frame.t()) :: t
  def new(%{stream_id: stream_id, payload: data, flags: flags}) do
    %__MODULE__{
      data: data,
      stream_id: stream_id,
      end_stream: end_stream?(flags)
    }
  end

  @spec end_stream?(non_neg_integer) :: boolean
  defp end_stream?(flags) when (flags &&& 1) == 1, do: true
  defp end_stream?(_), do: false
end
