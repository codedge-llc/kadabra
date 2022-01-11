defmodule Kadabra.Supervisor do
  @moduledoc ~S"""
  Supervisor to be used by the library user to add it to the desired supervision tree.
  This allows the library user to be more in control of how failures are managed.
  When using this, you probably don't want the Kadabra Application to be started.
  You can accomplish this by specifying in your dependency:

  ```elixir
    {:kadabra, app: false}
  ```

  You can add this to your supervision tree with the following spec:

  ```elixir
  {Kadabra.Supervisor, name: :custom_kadabra_supervisor}
  ```
  """

  use Supervisor

  def start_link(args) do
    name = Keyword.fetch!(args, :name)
    Supervisor.start_link(__MODULE__, name, name: :"Kadabra.Supervisor.#{name}")
  end

  @impl true
  def init(name) do
    children = [
      {Registry, keys: :unique, name: Registry.Kadabra},
      {Task.Supervisor, name: Kadabra.Tasks},
      {Kadabra.ConnectionSupervisor, instance_name: name}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
