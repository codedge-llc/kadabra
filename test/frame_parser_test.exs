defmodule Kadabra.FrameParserTest do
  use ExUnit.Case

  alias Kadabra.{Encodable, FrameParser}
  alias Kadabra.Frame.Goaway

  test "parses GOAWAY frame" do
    frame = Goaway.new(1, <<0, 0, 0, 0>>)
    bin = Encodable.to_bin(frame)

    assert {:ok, f, <<>>} = FrameParser.parse(bin)
    assert f == frame
  end
end
