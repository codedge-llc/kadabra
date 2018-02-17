defmodule Kadabra.Connection.SettingsTest do
  use ExUnit.Case
  doctest Kadabra.Connection.Settings, import: true

  describe "Encodable.to_bin/1" do
    test "encodes max_concurrent_streams" do
      bin_settings =
        %Kadabra.Connection.Settings{max_concurrent_streams: 250}
        |> Kadabra.Encodable.to_bin()

      assert bin_settings ==
               <<0, 5, 0, 0, 64, 0, 0, 3, 0, 0, 0, 250, 0, 4, 0, 0, 255, 255, 0,
                 1, 0, 0, 16, 0, 0, 2, 0, 0, 0, 1>>
    end

    test "encodes max_header_list_size" do
      bin_settings =
        %Kadabra.Connection.Settings{max_header_list_size: 24}
        |> Kadabra.Encodable.to_bin()

      assert bin_settings ==
               <<0, 6, 0, 0, 0, 24, 0, 5, 0, 0, 64, 0, 0, 4, 0, 0, 255, 255, 0,
                 1, 0, 0, 16, 0, 0, 2, 0, 0, 0, 1>>
    end
  end
end
