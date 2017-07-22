defmodule Kadabra.Connection.Settings do
  defstruct header_table_size: 4096,
            enable_push: true,
            max_concurrent_streams: nil,
            initial_window_size: 65_535,
            max_frame_size: 16_384,
            max_header_list_size: nil

  alias Kadabra.Error

  @table_header_size 0x1
  @enable_push 0x2
  @max_concurrent_streams 0x3
  @initial_window_size 0x4
  @max_frame_size 0x5
  @max_header_list_size 0x6

  def put(settings, @table_header_size, value) do
    {:ok, %{settings | table_header_size: value}}
  end

  def put(settings, @enable_push, 1) do
    {:ok, %{settings | enable_push: true}}
  end
  def put(settings, @enable_push, 0) do
    {:ok, %{settings | enable_push: false}}
  end
  def put(settings, @enable_push, _else) do
    {:error, Error.protocol_error, settings}
  end

  def put(settings, @max_concurrent_streams, value) do
    {:ok, %{settings | max_concurrent_streams: value}}
  end

  def put(settings, @initial_window_size, value) when value > 4_294_967_295 do
    {:error, Error.flow_control_error, settings}
  end
  def put(settings, @initial_window_size, value) do
    {:ok, %{settings | initial_window_size: value}}
  end

  def put(settings, @max_frame_size, value) when value > 16_777_215 or value < 16_384 do
    {:error, Error.protocol_error, settings}
  end
  def put(settings, @max_frame_size, value) do
    {:ok, %{settings | max_frame_size: value}}
  end

  def put(settings, @max_header_list_size, value) do
    {:ok, %{settings | max_header_list_size: value}}
  end

  def put(settings, _else, _value), do: {:ok, settings}
end
