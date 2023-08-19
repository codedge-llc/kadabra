defmodule Kadabra.Frame.Ping do
  @moduledoc false

  defstruct [:data, stream_id: 0, ack: false]

  import Bitwise

  alias Kadabra.Frame

  @type t :: %__MODULE__{
          ack: boolean,
          data: <<_::64>>,
          stream_id: integer
        }

  @doc ~S"""
  Returns new unacked ping frame.

  ## Examples

      iex> Kadabra.Frame.Ping.new
      %Kadabra.Frame.Ping{data: <<0, 0, 0, 0, 0, 0, 0, 0>>,
      ack: false, stream_id: 0}
  """
  @spec new() :: t
  def new do
    %__MODULE__{
      ack: false,
      data: <<0, 0, 0, 0, 0, 0, 0, 0>>,
      stream_id: 0
    }
  end

  @doc ~S"""
  Initializes a new `Frame.Ping` given a `Frame`.

  ## Examples

      iex> frame = %Kadabra.Frame{payload: <<0, 0, 0, 0, 0, 0, 0, 0>>,
      ...> flags: 0x1, type: 0x6, stream_id: 0}
      iex> Kadabra.Frame.Ping.new(frame)
      %Kadabra.Frame.Ping{data: <<0, 0, 0, 0, 0, 0, 0, 0>>, ack: true,
      stream_id: 0}
  """
  @spec new(Frame.t()) :: t
  def new(%Frame{type: 0x6, payload: <<data::64>>, flags: flags, stream_id: sid}) do
    %__MODULE__{
      ack: ack?(flags),
      data: <<data::64>>,
      stream_id: sid
    }
  end

  @spec ack?(non_neg_integer) :: boolean
  defp ack?(flags) when (flags &&& 1) == 1, do: true
  defp ack?(_), do: false
end
