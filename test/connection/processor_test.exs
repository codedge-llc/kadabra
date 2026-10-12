defmodule Kadabra.Connection.ProcessorTest do
  use ExUnit.Case

  alias Kadabra.{Connection, Encodable, FrameParser}
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

  describe "process SETTINGS" do
    defp settings_bin(payload) do
      <<byte_size(payload)::24, 0x4::8, 0x0::8, 0::1, 0::31, payload::binary>>
    end

    test "throws PROTOCOL_ERROR on invalid ENABLE_PUSH" do
      {:ok, frame, <<>>} = FrameParser.parse(settings_bin(<<0x2::16, 2::32>>))

      assert {:connection_error, :PROTOCOL_ERROR, _, _} =
               Processor.process(frame, conn())
    end

    test "throws FLOW_CONTROL_ERROR on INITIAL_WINDOW_SIZE above 2^31-1" do
      payload = <<0x4::16, 2_147_483_648::32>>
      {:ok, frame, <<>>} = FrameParser.parse(settings_bin(payload))

      assert {:connection_error, :FLOW_CONTROL_ERROR, _, _} =
               Processor.process(frame, conn())
    end

    test "throws PROTOCOL_ERROR on MAX_FRAME_SIZE out of range" do
      {:ok, frame, <<>>} = FrameParser.parse(settings_bin(<<0x5::16, 100::32>>))

      assert {:connection_error, :PROTOCOL_ERROR, _, _} =
               Processor.process(frame, conn())
    end

    test "valid SETTINGS still parse to a settings frame" do
      bin =
        %Kadabra.Frame.Settings{settings: %Connection.Settings{}}
        |> Encodable.to_bin()

      assert {:ok, %Kadabra.Frame.Settings{ack: false}, <<>>} =
               FrameParser.parse(bin)
    end
  end
end
