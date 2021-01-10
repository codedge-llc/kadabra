defmodule Kadabra.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Registry.Kadabra},
      {Task.Supervisor, name: Kadabra.Tasks}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: :kadabra)
  end
end
