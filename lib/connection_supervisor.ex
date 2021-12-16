defmodule Kadabra.ConnectionSupervisor do
  @moduledoc false

  use DynamicSupervisor

  def start_link(args) do
    instance_name = Keyword.fetch!(args, :instance_name)
    DynamicSupervisor.start_link(__MODULE__, nil, name: name(instance_name))
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_child(instance_name, opts) do
    spec = {Kadabra.ConnectionPool, opts}
    DynamicSupervisor.start_child(name(instance_name), spec)
  end

  defp name(instance_name) do
    :"Kadabra.ConnectionSupervisor.#{instance_name}"
  end
end
