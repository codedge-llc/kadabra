defmodule Kadabra.StreamTest do
  use ExUnit.Case
  doctest Kadabra.Stream

  alias Kadabra.{Connection, Frame, Stream}

  describe "recv/3" do
    test "keeps state on unknown stream" do
      stream = Stream.new(%Connection.Settings{}, 1)

      # Individual streams shouldn't get pings
      ping = Frame.Ping.new()
      assert stream == Stream.recv(stream, ping, %Connection{})
    end

    test "closes stream on RST_STREAM" do
      stream =
        %Connection.Settings{}
        |> Stream.new(1)
        |> Map.put(:state, :open)

      rst = Frame.RstStream.new(1)
      assert Stream.recv(stream, rst).state == :closed
    end

    test "closes stream on DATA with END_STREAM in hc_local state" do
      stream =
        %Connection.Settings{}
        |> Stream.new(1)
        |> Map.put(:state, :half_closed_local)

      data = %Frame.Data{stream_id: 1, data: "test", end_stream: true}

      assert Stream.recv(stream, data).state == :closed
    end
  end
end
