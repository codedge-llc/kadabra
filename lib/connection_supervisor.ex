defmodule Kadabra.ConnectionSupervisor do
  @moduledoc false

  use Supervisor
  import Supervisor.Spec

  alias Kadabra.{Connection, Hpack}

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

  def start_connection(uri, pid, ref, opts) do
    spec = worker(Connection, [uri, pid, ref, opts], id: :connection)
    Supervisor.start_child(via_tuple(ref), spec)
  end

  def init({uri, pid, sup, ref, opts}) do
    children = [
      worker(Hpack, [{ref, :encoder}], start_opts(:encoder)),
      worker(Hpack, [{ref, :decoder}], start_opts(:decoder)),
      worker(Connection, [uri, pid, sup, ref, opts], start_opts(:connection))
    ]

    supervise(children, strategy: :one_for_all)
  end
end
