defmodule Kadabra.Frame.PushPromise do
  @moduledoc false

  defstruct end_headers: false,
            header_block_fragment: nil,
            stream_id: nil

  import Bitwise

  alias Kadabra.Frame

  @type t :: %__MODULE__{
          end_headers: boolean,
          header_block_fragment: bitstring,
          stream_id: non_neg_integer
        }

  @doc ~S"""
  Initializes a new `Frame.PushPromise` given a `Frame`.

  ## Examples

      iex> frame = %Kadabra.Frame{payload: <<0::1, 3::31, 136::8>>, flags: 0x4}
      iex> Kadabra.Frame.PushPromise.new(frame)
      %Kadabra.Frame.PushPromise{stream_id: 3, header_block_fragment: <<136>>,
      end_headers: true}
  """
  @spec new(Frame.t()) :: t
  def new(%Frame{payload: <<_::1, id::31, headers::bitstring>>, flags: f}) do
    %__MODULE__{
      stream_id: id,
      header_block_fragment: headers,
      end_headers: end_headers?(f)
    }
  end

  @spec end_headers?(non_neg_integer) :: boolean
  defp end_headers?(flags) when (flags &&& 4) == 4, do: true
  defp end_headers?(_), do: false
end
