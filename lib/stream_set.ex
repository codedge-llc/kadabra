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

  @spec increment_stream_id(t) :: t
  def increment_stream_id(stream_set) do
    %{stream_set | stream_id: stream_set.stream_id + 2}
  end

  @spec increment_active_stream_count(t) :: t
  def increment_active_stream_count(stream_set) do
    %{stream_set | active_stream_count: stream_set.active_stream_count + 1}
  end

  @spec decrement_active_stream_count(t) :: t
  def decrement_active_stream_count(stream_set) do
    %{stream_set | active_stream_count: stream_set.active_stream_count - 1}
  end

  def add_active(%{active_streams: active} = stream_set, stream_id, pid) do
    %{stream_set | active_streams: Map.put(active, stream_id, pid)}
  end

  def remove_active(%{active_streams: active} = stream_set, stream_id)
      when is_integer(stream_id) do
    %{stream_set | active_streams: Map.delete(active, stream_id)}
  end

  @spec can_send?(t) :: boolean
  def can_send?(%{active_stream_count: count, max_concurrent_streams: max})
      when count < max,
      do: true

  def can_send?(_else), do: false
end
