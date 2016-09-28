defmodule Dos.Connection do
  use GenServer

  def start_link(config) do
    GenServer.start_link(__MODULE__, {:ok, config})
  end

  def init({:ok, config}), do: {:ok, config}
end
