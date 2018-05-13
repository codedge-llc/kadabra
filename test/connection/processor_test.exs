defmodule Kadabra.Connection.ProcessorTest do
  use ExUnit.Case

  alias Kadabra.Connection
  alias Kadabra.Connection.Processor
  alias Kadabra.Frame.{Data, Ping, WindowUpdate}

  defp conn do
    %Connection{
      config: %{
        client: self()
      },
      flow_control: %Connection.FlowControl{}
    }
  end

  test "throws connection error on non-zero DATA stream_id" do
    bad = %Data{stream_id: 0}

    assert {:connection_error, :PROTOCOL_ERROR, _, _} =
             Processor.process(bad, conn())
  end

  describe "process PING" do
    test "throws connection error on non-zero stream_id" do
      bad = %Ping{stream_id: 1}

      assert {:connection_error, :PROTOCOL_ERROR, _, _} =
               Processor.process(bad, conn())
    end

    test "throws connection error if payload not 8 bytes" do
      bad = %Ping{data: <<0, 1>>}

      assert {:connection_error, :FRAME_SIZE_ERROR, _, _} =
               Processor.process(bad, conn())
    end
  end

  describe "process WINDOW_UPDATE" do
    test "throws connection error zero or negative increment" do
      bad = %WindowUpdate{window_size_increment: 0, stream_id: 0}
      bad_2 = %WindowUpdate{window_size_increment: -5, stream_id: 0}

      for b <- [bad, bad_2] do
        assert {:connection_error, :PROTOCOL_ERROR, _, _} =
                 Processor.process(b, conn())
      end
    end
  end
end
