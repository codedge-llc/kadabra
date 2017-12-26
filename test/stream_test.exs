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
  end
end
