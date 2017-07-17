defmodule Kadabra.Frame.PushPromise do
  defstruct [:stream_id, :header_block_fragment, end_headers: false]

  alias Kadabra.Frame.Flags

  def new(%{payload: <<_::1, stream_id::31, headers::bitstring>>,
            flags: flags}) do

    %__MODULE__{
      stream_id: stream_id,
      header_block_fragment: headers,
      end_headers: Flags.end_headers?(flags)
    }
  end

  def new(<<payload_size::24,
            frame_type::8,
            flags::8,
            _::1,
            _stream_id::31,
            _::1,
            stream_id::31,
            headers::bitstring>> = bin) do

    %__MODULE__{
      stream_id: stream_id,
      header_block_fragment: headers,
      end_headers: Flags.end_headers?(flags)
    }
  end
end
