defmodule Kadabra.ConnectionSupervisor do
  @moduledoc false

  use Supervisor
  import Supervisor.Spec

  alias Kadabra.{Connection, ConnectionQueue, Hpack}

  def start_link(uri, pid, sup, ref, opts) do
    name = via_tuple(ref)
    Supervisor.start_link(__MODULE__, {uri, pid, sup, ref, opts}, name: name)
  end

  def via_tuple(ref) do
    {:via, Registry, {Registry.Kadabra, {ref, __MODULE__}}}
  end

  def start_opts(id \\ :erlang.make_ref) do
    [id: id, restart: :transient]
  end

  def init({uri, pid, sup, ref, opts}) do
    children = [
      worker(Hpack, [{ref, :encoder}], start_opts(:encoder)),
      worker(Hpack, [{ref, :decoder}], start_opts(:decoder)),
      worker(ConnectionQueue, [sup], start_opts(:connection_queue)),
      worker(Connection, [uri, pid, sup, ref, opts], start_opts(:connection))
    ]

    supervise(children, strategy: :one_for_all)
  end
end
