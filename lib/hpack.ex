defmodule Kadabra.Hpack do
  @moduledoc false

  use GenServer

  def start_link({ref, name}) do
    id = via_tuple(ref, name)
    GenServer.start_link(__MODULE__, :ok, name: id)
  end

  def via_tuple(ref, name) do
    {:via, Registry, {Registry.Kadabra, {ref, name}}}
  end

  def init(:ok) do
    {:ok, :hpack.new_context}
  end

  def encode(ref, headers) do
    GenServer.call(via_tuple(ref, :encoder), {:encode, headers})
  end

  def decode(ref, headers) do
    GenServer.call(via_tuple(ref, :decoder), {:decode, headers})
  end

  def update_max_table_size(pid, size) do
    GenServer.call(pid, {:new_max_table_size, size})
  end

  def close(ref) do
    GenServer.stop(via_tuple(ref, :encoder), :normal, 5_000)
    GenServer.stop(via_tuple(ref, :decoder), :normal, 5_000)
  end

  def handle_call({:encode, headers}, _pid, state) do
    {:ok, {bin, new_state}} = :hpack.encode(headers, state)
    {:reply, {:ok, bin}, new_state}
  end

  def handle_call({:decode, header_block_fragment}, _pid, state) do
    {:ok, {headers, new_state}} = :hpack.decode(header_block_fragment, state)
    {:reply, {:ok, headers}, new_state}
  end

  def handle_call({:new_max_table_size, size}, _pid, state) do
    new_state = :hpack.new_max_table_size(size, state)
    {:reply, :ok, new_state}
  end
end
