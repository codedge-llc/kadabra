defmodule Kadabra.Supervisor do
  @moduledoc false

  use Supervisor
  import Supervisor.Spec

  alias Kadabra.{Connection, ConnectionQueue, Hpack}

  def start_link(uri, pid, opts) do
    ref = :erlang.make_ref()
    Supervisor.start_link(__MODULE__, {uri, pid, ref, opts})
  end

  def stop(pid) do
    Supervisor.stop(pid)
  end

  def start_opts(id \\ :erlang.make_ref()) do
    [id: id, restart: :transient]
  end

  def init({uri, pid, ref, opts}) do
    children = [
      worker(Hpack, [ref, :encoder], id: :encoder),
      worker(Hpack, [ref, :decoder], id: :decoder),
      worker(ConnectionQueue, [self()], id: :connection_queue),
      worker(Connection, [uri, pid, self(), ref, opts], id: :connection)
    ]

    supervise(children, strategy: :one_for_all)
  end
end
