defmodule Kadabra.ConnectionSettings do
  @moduledoc false

  use GenServer

  alias Kadabra.Connection

  def start_link(ref) do
    GenServer.start_link(__MODULE__, :ok, name: via_tuple(ref))
  end

  def init(:ok) do
    {:ok, %Kadabra.Connection.Settings{}}
  end

  def via_tuple(ref) do
    {:via, Registry, {Registry.Kadabra, {ref, :settings}}}
  end

  def update(ref, settings) do
    name = via_tuple(ref)
    GenServer.call(name, {:put, settings})
  end

  def fetch(ref) do
    name = via_tuple(ref)
    GenServer.call(name, :fetch)
  end

  def handle_call({:put, settings}, _pid, old_settings) do
    settings = Connection.Settings.merge(old_settings, settings)
    {:reply, {:ok, settings}, settings}
  end

  def handle_call(:fetch, _pid, settings) do
    {:reply, {:ok, settings}, settings}
  end
end
