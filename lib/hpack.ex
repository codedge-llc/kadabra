defmodule Kadabra.Hpack do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    {:ok, :hpack.new_context}
  end

  def encode(pid, headers) do
    GenServer.call(pid, {:encode, headers})
  end

  def decode(pid, headers) do
    GenServer.call(pid, {:decode, headers})
  end

  def update_max_table_size(pid, size) do
    GenServer.call(pid, {:new_max_table_size, size})
  end

  def handle_call({:encode, headers}, pid, state) do
    {:ok, {bin, new_state}} = :hpack.encode(headers, state)
    {:reply, {:ok, bin}, new_state}
  end

  def handle_call({:decode, header_block_fragment}, pid, state) do
    {:ok, {headers, new_state}} = :hpack.decode(header_block_fragment, state)
    {:reply, {:ok, headers}, new_state}
  end

  def handle_call({:new_max_table_size, size}, pid, state) do
    new_state = :hpack.new_max_table_size(size, state)
    {:reply, :ok, new_state}
  end
end
