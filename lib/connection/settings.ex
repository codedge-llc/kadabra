defmodule Kadabra.Connection.Settings do
  @moduledoc false

  @default_header_table_size 4096
  @default_initial_window_size round(:math.pow(2, 16) - 1)
  @default_max_frame_size round(:math.pow(2, 14))

  defstruct enable_push: true,
            header_table_size: @default_header_table_size,
            initial_window_size: @default_initial_window_size,
            max_concurrent_streams: :infinite,
            max_frame_size: @default_max_frame_size,
            max_header_list_size: nil

  alias Kadabra.Connection.Error

  @type t :: %__MODULE__{
          header_table_size: non_neg_integer,
          enable_push: boolean,
          max_concurrent_streams: non_neg_integer | :infinite,
          initial_window_size: non_neg_integer,
          max_frame_size: non_neg_integer,
          max_header_list_size: non_neg_integer
        }

  @table_header_size 0x1
  @enable_push 0x2
  @max_concurrent_streams 0x3
  @initial_window_size 0x4
  @max_frame_size 0x5
  @max_header_list_size 0x6

  @max_initial_window_size round(:math.pow(2, 31) - 1)
  @max_max_frame_size round(:math.pow(2, 24) - 1)

  def default do
    %__MODULE__{}
  end

  def fastest do
    %__MODULE__{
      initial_window_size: @max_initial_window_size,
      max_frame_size: @max_max_frame_size
    }
  end

  @doc ~S"""
  Puts setting value, returning an error if present.

  ## Examples

      iex> s = %Kadabra.Connection.Settings{}
      iex> enable_push = 0x2
      iex> Kadabra.Connection.Settings.put(s, enable_push, 1)
      {:ok, %Kadabra.Connection.Settings{enable_push: true}}
      iex> Kadabra.Connection.Settings.put(s, enable_push, :bad)
      {:error, Kadabra.Connection.Error.protocol_error, s}

      iex> s = %Kadabra.Connection.Settings{}
      iex> init_window_size = 0x4
      iex> Kadabra.Connection.Settings.put(s, init_window_size, 70_000)
      {:ok, %Kadabra.Connection.Settings{initial_window_size: 70_000}}
      iex> Kadabra.Connection.Settings.put(s, init_window_size, 5_000_000_000)
      {:error, Kadabra.Connection.Error.flow_control_error, s}

      iex> s = %Kadabra.Connection.Settings{}
      iex> max_frame_size = 0x5
      iex> Kadabra.Connection.Settings.put(s, max_frame_size, 20_000)
      {:ok, %Kadabra.Connection.Settings{max_frame_size: 20_000}}
      iex> Kadabra.Connection.Settings.put(s, max_frame_size, 20_000_000)
      {:error, Kadabra.Connection.Error.protocol_error, s}
      iex> Kadabra.Connection.Settings.put(s, max_frame_size, 2_000)
      {:error, Kadabra.Connection.Error.protocol_error, s}
  """
  @spec put(t, non_neg_integer, term) :: {:ok, t} | {:error, binary, t}
  def put(settings, @table_header_size, value) do
    {:ok, %{settings | header_table_size: value}}
  end

  def put(settings, @enable_push, 1) do
    {:ok, %{settings | enable_push: true}}
  end

  def put(settings, @enable_push, 0) do
    {:ok, %{settings | enable_push: false}}
  end

  def put(settings, @enable_push, _else) do
    {:error, Error.protocol_error(), settings}
  end

  def put(settings, @max_concurrent_streams, value) do
    {:ok, %{settings | max_concurrent_streams: value}}
  end

  def put(settings, @initial_window_size, value)
      when value > @max_initial_window_size do
    {:error, Error.flow_control_error(), settings}
  end

  def put(settings, @initial_window_size, value) do
    {:ok, %{settings | initial_window_size: value}}
  end

  def put(settings, @max_frame_size, value)
      when value < @default_max_frame_size or value > @max_max_frame_size do
    {:error, Error.protocol_error(), settings}
  end

  def put(settings, @max_frame_size, value) do
    {:ok, %{settings | max_frame_size: value}}
  end

  def put(settings, @max_header_list_size, value) do
    {:ok, %{settings | max_header_list_size: value}}
  end

  def put(settings, _else, _value), do: {:ok, settings}

  def merge(nil, new_settings), do: new_settings

  def merge(old_settings, new_settings) do
    Map.merge(old_settings, new_settings, fn k, v1, v2 ->
      cond do
        k == :__struct__ -> v1
        v1 == nil -> v2
        v2 == nil -> v1
        true -> v2
      end
    end)
  end
end
