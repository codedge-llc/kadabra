defmodule Kadabra.ConnectionSettings do
  use GenServer

  alias Kadabra.Connection

  def start_link do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    {:ok, %Kadabra.Connection.Settings{}}
  end

  def update(pid, settings) do
    GenServer.call(pid, {:put, settings})
  end

  def fetch(pid) do
    GenServer.call(pid, :fetch)
  end

  def handle_call({:put, settings}, _pid, old_settings) do
    settings = Connection.Settings.merge(old_settings, settings)
    #IO.inspect(settings, label: "new settings")
    {:reply, {:ok, settings}, settings}
  end

  def handle_call(:fetch, _pid, settings) do
    {:reply, {:ok, settings}, settings}
  end
end
