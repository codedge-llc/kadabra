defmodule Kadabra.Frame.Data do
  @moduledoc false

  defstruct [:stream_id, :data, end_stream: false]

  alias Kadabra.Frame
  alias Kadabra.Frame.Flags

  @type t :: %__MODULE__{
    data: binary,
    end_stream: boolean,
    stream_id: pos_integer
  }

  @spec new(Frame.t) :: t
  def new(%{stream_id: stream_id, payload: data, flags: flags}) do
    %__MODULE__{
      data: data,
      stream_id: stream_id,
      end_stream: Flags.end_stream?(flags)
    }
  end
end
