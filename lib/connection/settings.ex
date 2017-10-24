defmodule Kadabra.Connection.Settings do
  @moduledoc false

  defstruct enable_push: true,
            header_table_size: 4096,
            initial_window_size: 65_535,
            max_concurrent_streams: :infinite,
            max_frame_size: 16_384,
            max_header_list_size: nil

  alias Kadabra.Error

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

  def default do
    %__MODULE__{}
  end

  @doc ~S"""
  Puts setting value, returning an error if present.

  ## Examples

      iex> s = %Kadabra.Connection.Settings{}
      iex> enable_push = 0x2
      iex> Kadabra.Connection.Settings.put(s, enable_push, 1)
      {:ok, %Kadabra.Connection.Settings{enable_push: true}}
      iex> Kadabra.Connection.Settings.put(s, enable_push, :bad)
      {:error, Kadabra.Error.protocol_error, s}

      iex> s = %Kadabra.Connection.Settings{}
      iex> init_window_size = 0x4
      iex> Kadabra.Connection.Settings.put(s, init_window_size, 70_000)
      {:ok, %Kadabra.Connection.Settings{initial_window_size: 70_000}}
      iex> Kadabra.Connection.Settings.put(s, init_window_size, 5_000_000_000)
      {:error, Kadabra.Error.flow_control_error, s}

      iex> s = %Kadabra.Connection.Settings{}
      iex> max_frame_size = 0x5
      iex> Kadabra.Connection.Settings.put(s, max_frame_size, 20_000)
      {:ok, %Kadabra.Connection.Settings{max_frame_size: 20_000}}
      iex> Kadabra.Connection.Settings.put(s, max_frame_size, 20_000_000)
      {:error, Kadabra.Error.protocol_error, s}
      iex> Kadabra.Connection.Settings.put(s, max_frame_size, 2_000)
      {:error, Kadabra.Error.protocol_error, s}
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

  def put(settings, @max_frame_size, value) do
    if value < 16_384 or value > 16_777_215 do
      {:error, Error.protocol_error, settings}
    else
      {:ok, %{settings | max_frame_size: value}}
    end
  end

  def put(settings, @max_header_list_size, value) do
    {:ok, %{settings | max_header_list_size: value}}
  end

  def put(settings, _else, _value), do: {:ok, settings}

  def merge(old_settings, new_settings) do
    Map.merge(old_settings, new_settings, fn(k, v1, v2) ->
      cond do
        k == :__struct__ -> v1
        v1 == nil -> v2
        v2 == nil -> v1
        true -> v2
      end
    end)
  end
end

defimpl Kadabra.Encodable, for: Kadabra.Connection.Settings do
  def to_bin(settings) do
    settings
    |> Map.from_struct
    |> to_encoded_list()
    |> Enum.join
  end

  def to_encoded_list(settings) do
    Enum.reduce(settings, [], fn({k, v}, acc) ->
      case v do
        nil -> acc
        :infinite -> acc
        v -> [encode_setting(k, v)] ++ acc
      end
    end)
  end

  def encode_setting(:header_table_size, v), do:      <<0x1::16, v::32>>
  def encode_setting(:enable_push, true), do:         <<0x2::16, 1::32>>
  def encode_setting(:enable_push, false), do:        <<0x2::16, 0::32>>
  def encode_setting(:max_concurrent_streams, v), do: <<0x3::16, v::32>>
  def encode_setting(:initial_window_size, v), do:    <<0x4::16, v::32>>
  def encode_setting(:max_frame_size, v), do:         <<0x5::16, v::32>>
  def encode_setting(:max_header_list_size, v), do:   <<0x6::16, v::32>>
end
