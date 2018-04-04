defmodule Kadabra.Tasks do
  @moduledoc false

  def run(nil, _response), do: :ok

  def run(fun, response) do
    Task.Supervisor.start_child(Kadabra.Tasks, fn -> fun.(response) end)
  end
end
