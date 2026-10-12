defmodule Kadabra.Frame.SettingsTest do
  use ExUnit.Case

  alias Kadabra.{Connection, Error, Frame}

  defp frame(payload, flags \\ 0x0) do
    %Frame{type: 0x4, stream_id: 0, flags: flags, payload: payload}
  end

  describe "new/1" do
    test "returns default settings for an empty payload" do
      assert %Frame.Settings{settings: nil, ack: false} =
               Frame.Settings.new(frame(""))
    end

    test "parses an ACK" do
      assert %Frame.Settings{settings: nil, ack: true} =
               Frame.Settings.new(frame("", 0x1))
    end

    test "parses valid settings" do
      payload = <<0x3::16, 100::32, 0x4::16, 70_000::32, 0x6::16, 8_192::32>>

      assert %Frame.Settings{settings: settings, ack: false} =
               Frame.Settings.new(frame(payload))

      assert %Connection.Settings{
               max_concurrent_streams: 100,
               initial_window_size: 70_000,
               max_header_list_size: 8_192
             } = settings
    end

    test "returns PROTOCOL_ERROR for ENABLE_PUSH other than 0 or 1" do
      payload = <<0x2::16, 2::32>>

      assert Frame.Settings.new(frame(payload)) ==
               {:error, Error.protocol_error()}
    end

    test "returns FLOW_CONTROL_ERROR for INITIAL_WINDOW_SIZE above 2^31-1" do
      payload = <<0x4::16, 2_147_483_648::32>>

      assert Frame.Settings.new(frame(payload)) ==
               {:error, Error.flow_control_error()}
    end

    test "returns PROTOCOL_ERROR for MAX_FRAME_SIZE out of range" do
      for size <- [16_383, 16_777_216] do
        payload = <<0x5::16, size::32>>

        assert Frame.Settings.new(frame(payload)) ==
                 {:error, Error.protocol_error()}
      end
    end

    test "returns the error even when it follows valid settings" do
      payload = <<0x3::16, 100::32, 0x2::16, 7::32>>

      assert Frame.Settings.new(frame(payload)) ==
               {:error, Error.protocol_error()}
    end
  end
end
