defmodule Kadabra.StreamSet do
  @moduledoc false

  defstruct stream_id: 1,
            active_stream_count: 0,
            active_streams: %{},
            max_concurrent_streams: :infinite

  @type t :: %__MODULE__{
          stream_id: pos_integer,
          active_stream_count: non_neg_integer,
          active_streams: MapSet.t(),
          max_concurrent_streams: non_neg_integer | :infinite
        }

  def pid_for(set, stream_id) do
    set.active_streams[stream_id]
  end

  @doc ~S"""
  Increments current `stream_id`.

  ## Examples

      iex> set = %Kadabra.StreamSet{stream_id: 5}
      iex> increment_stream_id(set)
      %Kadabra.StreamSet{stream_id: 7}
  """
  @spec increment_stream_id(t) :: t
  def increment_stream_id(stream_set) do
    %{stream_set | stream_id: stream_set.stream_id + 2}
  end

  @doc ~S"""
  Increments open stream count.

  ## Examples

      iex> set = %Kadabra.StreamSet{active_stream_count: 2}
      iex> increment_active_stream_count(set)
      %Kadabra.StreamSet{active_stream_count: 3}
  """
  @spec increment_active_stream_count(t) :: t
  def increment_active_stream_count(stream_set) do
    %{stream_set | active_stream_count: stream_set.active_stream_count + 1}
  end

  @doc ~S"""
  Decrements open stream count.

  ## Examples

      iex> set = %Kadabra.StreamSet{active_stream_count: 2}
      iex> decrement_active_stream_count(set)
      %Kadabra.StreamSet{active_stream_count: 1}
  """
  @spec decrement_active_stream_count(t) :: t
  def decrement_active_stream_count(stream_set) do
    %{stream_set | active_stream_count: stream_set.active_stream_count - 1}
  end

  @doc ~S"""
  Marks stream_id as active.

  ## Examples

      iex> set = add_active(%Kadabra.StreamSet{}, 1, :dummy)
      iex> set.active_streams
      %{1 => :dummy}
  """
  def add_active(%{active_streams: active} = stream_set, stream_id, pid) do
    %{stream_set | active_streams: Map.put(active, stream_id, pid)}
  end

  @doc ~S"""
  Removes stream_id from active set.

  ## Examples

      iex> set = %Kadabra.StreamSet{active_streams: %{1 => :test, 3 => :dummy}}
      iex> remove_active(set, 1).active_streams
      %{3 => :dummy}
  """
  def remove_active(%{active_streams: active} = stream_set, stream_id)
      when is_integer(stream_id) do
    %{stream_set | active_streams: Map.delete(active, stream_id)}
  end

  @doc ~S"""
  Returns true if active_streams is less than max streams.

  ## Examples

      iex> set = %Kadabra.StreamSet{active_stream_count: 3,
      ...> max_concurrent_streams: 100}
      iex> can_send?(set)
      true

      iex> set = %Kadabra.StreamSet{active_stream_count: 3,
      ...> max_concurrent_streams: 1}
      iex> can_send?(set)
      false
  """
  @spec can_send?(t) :: boolean
  def can_send?(%{active_stream_count: count, max_concurrent_streams: max})
      when count < max,
      do: true

  def can_send?(_else), do: false
end
