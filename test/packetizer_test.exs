defmodule Kadabra.PacketizerTest do
  use ExUnit.Case

  alias Kadabra.{Frame, Packetizer}

  test "packetizes correctly" do
    bin = String.duplicate("test", 6)
    actual = Packetizer.headers(1, bin, 10, true)

    expected = [
      %Frame.Headers{
        stream_id: 1,
        end_stream: true,
        end_headers: false,
        header_block_fragment: "testtestte"
      },
      %Frame.Continuation{
        stream_id: 1,
        end_headers: false,
        header_block_fragment: "sttesttest"
      },
      %Frame.Continuation{
        stream_id: 1,
        end_headers: true,
        header_block_fragment: "test"
      }
    ]

    assert actual == expected
  end
end
