defmodule Kadabra.Application do
  @moduledoc false

  use Application
  import Supervisor.Spec

  def start(_type, _args) do
    children = [
      supervisor(Registry, [:unique, Registry.Kadabra]),
      supervisor(Task.Supervisor, [[name: Kadabra.Tasks]])
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: :kadabra)
  end
end
