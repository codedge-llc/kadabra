defmodule Kadabra.StreamTest do
  use ExUnit.Case
  doctest Kadabra.Stream

  describe "recv/3" do
    test "keeps state on unknown stream" do
      stream = Kadabra.Stream.new(%Kadabra.Connection{})

      # Individual streams shouldn't get pings
      ping = Kadabra.Frame.Ping.new
      assert {:keep_state, ^stream} = Kadabra.Stream.recv(ping, :idle, stream)
    end
  end
end
