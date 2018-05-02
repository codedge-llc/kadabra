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

  @spec new(Frame.t()) :: t
  def new(%{stream_id: stream_id, payload: data, flags: flags}) do
    %__MODULE__{
      data: data,
      stream_id: stream_id,
      end_stream: Flags.end_stream?(flags)
    }
  end
end

defimpl Kadabra.Encodable, for: Kadabra.Frame.Data do
  alias Kadabra.Frame

  @data 0x0

  def to_bin(frame) do
    end_stream = if frame.end_stream, do: 0x1, else: 0x0
    Frame.binary_frame(@data, end_stream, frame.stream_id, frame.data)
  end
end
