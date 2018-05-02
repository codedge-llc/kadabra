defmodule Kadabra.Frame.Ping do
  @moduledoc false

  defstruct [:data, ack: false]

  alias Kadabra.Frame
  alias Kadabra.Frame.Flags

  @type t :: %__MODULE__{
          ack: boolean,
          data: <<_::64>>
        }

  @doc ~S"""
  Returns new unacked ping frame.

  ## Examples

      iex> Kadabra.Frame.Ping.new
      %Kadabra.Frame.Ping{data: <<0, 0, 0, 0, 0, 0, 0, 0>>,
      ack: false}
  """
  @spec new() :: t
  def new do
    %__MODULE__{
      ack: false,
      data: <<0, 0, 0, 0, 0, 0, 0, 0>>
    }
  end

  @doc ~S"""
  Initializes a new `Frame.Ping` given a `Frame`.

  ## Examples

      iex> frame = %Kadabra.Frame{payload: <<0, 0, 0, 0, 0, 0, 0, 0>>,
      ...> flags: 0x1, type: 0x6}
      iex> Kadabra.Frame.Ping.new(frame)
      %Kadabra.Frame.Ping{data: <<0, 0, 0, 0, 0, 0, 0, 0>>, ack: true}
  """
  @spec new(Frame.t()) :: t
  def new(%Frame{type: 0x6, payload: <<data::64>>, flags: flags}) do
    %__MODULE__{
      ack: Flags.ack?(flags),
      data: <<data::64>>
    }
  end
end

defimpl Kadabra.Encodable, for: Kadabra.Frame.Ping do
  alias Kadabra.Frame
  alias Kadabra.Frame.Flags

  def to_bin(frame) do
    ack = if frame.ack, do: Flags.ack(), else: 0x0
    Frame.binary_frame(0x6, ack, 0x0, frame.data)
  end
end
