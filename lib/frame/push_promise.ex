defmodule Kadabra.Frame.PushPromise do
  @moduledoc false

  defstruct end_headers: false,
            header_block_fragment: nil,
            headers: [],
            stream_id: nil

  alias Kadabra.Frame.Flags

  @type t :: %__MODULE__{
    end_headers: boolean,
    header_block_fragment: binary,
    headers: [...],
    stream_id: pos_integer
  }

  def new(%{payload: <<_::1, stream_id::31, headers::bitstring>>,
            flags: flags}) do

    %__MODULE__{
      stream_id: stream_id,
      header_block_fragment: headers,
      end_headers: Flags.end_headers?(flags)
    }
  end

  def new(<<_payload_size::24,
            _frame_type::8,
            flags::8,
            _::1,
            _stream_id::31,
            _::1,
            stream_id::31,
            headers::bitstring>>) do

    %__MODULE__{
      stream_id: stream_id,
      header_block_fragment: headers,
      end_headers: Flags.end_headers?(flags)
    }
  end
end
