defmodule Kadabra.Tasks do
  @moduledoc false

  def run(fun) do
    Task.Supervisor.start_child(Kadabra.Tasks, fn -> fun.() end)
  end

  def run(nil, _response), do: :ok

  def run(fun, response) do
    Task.Supervisor.start_child(Kadabra.Tasks, fn -> fun.(response) end)
  end
end
