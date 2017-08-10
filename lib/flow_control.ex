defmodule Kadabra.FlowControl do
  defstruct active_stream_count: 0,
            max_stream_count: :infinite,
            bytes_remaining: 65_535

  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    {:ok, %Kadabra.FlowControl{}}
  end

  def increment_active_stream_count(pid) do
    GenServer.call(pid, :inc_stream_count)
  end

  def decrement_active_stream_count(pid) do
    GenServer.call(pid, :dec_stream_count)
  end

  def set_max_stream_count(pid, new_max) do
    GenServer.call(pid, {:set_max_stream_count, new_max})
  end

  def can_send?(pid) do
    GenServer.call(pid, :can_send?)
  end

  def add_bytes(pid, bytes) do
    GenServer.call(pid, {:add_bytes, bytes})
  end

  def remove_bytes(pid, bytes) do
    GenServer.call(pid, {:remove_bytes, bytes})
  end

  def handle_call(:inc_stream_count, _pid, %{active_stream_count: count} = state) do
    #IO.puts("#{count} -> #{count + 1}")
    state = %{state | active_stream_count: count + 1}
    {:reply, {:ok, state.active_stream_count}, state}
  end

  def handle_call(:dec_stream_count, _pid, %{active_stream_count: count} = state) do
    #IO.puts("#{count} -> #{count - 1}")
    state = %{state | active_stream_count: count - 1}
    {:reply, {:ok, state.active_stream_count}, state}
  end

  def handle_call(:can_send?, _pid, %{bytes_remaining: bytes,
                                      active_stream_count: count,
                                      max_stream_count: max} = state) when bytes > 0 and count < max do
    #IO.puts("#{count} / #{max}")
    {:reply, true, state}
  end
  def handle_call(:can_send?, _pid, state) do
    {:reply, false, state}
  end

  def handle_call({:set_max_stream_count, max}, _pid, state) do
    {:reply, {:ok, max}, %{state | max_stream_count: max}}
  end

  def handle_call({:add_bytes, bytes}, _pid, %{bytes_remaining: b_rem} = state) do
    new_rem = b_rem + bytes
    {:reply, {:ok, new_rem}, %{state | bytes_remaining: new_rem}}
  end

  def handle_call({:remove_bytes, bytes}, _pid, %{bytes_remaining: b_rem} = state) do
    new_rem = b_rem - bytes
    {:reply, {:ok, new_rem}, %{state | bytes_remaining: new_rem}}
  end
end
