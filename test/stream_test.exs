defmodule Kadabra.StreamTest do
  use ExUnit.Case
  doctest Kadabra.Stream

  alias Kadabra.{Connection, Frame, Stream}

  describe "recv/3" do
    test "keeps state on unknown stream" do
      stream = Stream.new(%Connection{}, %Connection.Settings{}, 1)

      # Individual streams shouldn't get pings
      ping = Frame.Ping.new()
      assert {:keep_state, ^stream} = Stream.recv(ping, :idle, stream)
    end

    test "closes stream on RST_STREAM" do
      stream = Stream.new(%Connection{}, %Connection.Settings{}, 1)

      rst = Frame.RstStream.new(1)
      assert {:next_state, :closed, ^stream} = Stream.recv(rst, :open, stream)
    end

    test "closes stream on DATA with END_STREAM in hc_local state" do
      stream = Stream.new(%Connection{}, %Connection.Settings{}, 1)
      data = %Frame.Data{stream_id: 1, data: "test", end_stream: true}

      assert {:next_state, :closed, _stream} =
               Stream.recv(data, :half_closed_local, stream)
    end
  end
end
