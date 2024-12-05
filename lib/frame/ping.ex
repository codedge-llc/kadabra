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

  @empty_payload <<0, 0, 0, 0, 0, 0, 0, 0>>

  @doc ~S"""
  Returns new unacked ping frame. Optionally takes a payload of 8 bytes, which
  can be used to help calculate RTT times of pings that your application sends.

  Can also be used to initialize a new `Frame.Ping` given a `Frame`.

  ## Examples

      iex> Kadabra.Frame.Ping.new
      %Kadabra.Frame.Ping{data: <<0, 0, 0, 0, 0, 0, 0, 0>>,
      ack: false, stream_id: 0}
      iex> Kadabra.Frame.Ping.new(payload: <<1, 2, 3, 4, 5, 6, 7, 8>>)
      %Kadabra.Frame.Ping{data: <<1, 2, 3, 4, 5, 6, 7, 8>>,
      ack: false, stream_id: 0}
      iex> frame = %Kadabra.Frame{payload: <<0, 0, 0, 0, 0, 0, 0, 0>>,
      ...> flags: 0x1, type: 0x6, stream_id: 0}
      iex> Kadabra.Frame.Ping.new(frame)
      %Kadabra.Frame.Ping{data: <<0, 0, 0, 0, 0, 0, 0, 0>>, ack: true,
      stream_id: 0}
  """
  @spec new(<<_::64>> | none() | Frame.t()) :: t
  def new(nil), do: new(@empty_payload)

  def new(<<data::64>>) do
    %__MODULE__{
      ack: false,
      data: <<data::64>>,
      stream_id: 0
    }
  end

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
