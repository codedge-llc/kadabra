defmodule Kadabra.Supervisor do
  @moduledoc false

  use Supervisor
  import Supervisor.Spec

  alias Kadabra.{Connection, ConnectionQueue, Hpack, Socket}

  def start_link(uri, pid, opts) do
    config = %Kadabra.Config{
      ref: :erlang.make_ref(),
      client: pid,
      uri: uri,
      opts: opts
    }

    Supervisor.start_link(__MODULE__, config)
  end

  def stop(pid) do
    Supervisor.stop(pid)
  end

  def start_opts(id \\ :erlang.make_ref()) do
    [id: id, restart: :transient]
  end

  def init(%Kadabra.Config{ref: ref} = config) do
    config = %{config | supervisor: self()}

    children = [
      worker(ConnectionQueue, [self()], id: :connection_queue),
      worker(Socket, [config], id: :socket),
      worker(Hpack, [ref, :encoder], id: :encoder),
      worker(Hpack, [ref, :decoder], id: :decoder),
      worker(Connection, [config], id: :connection)
    ]

    supervise(children, strategy: :one_for_all)
  end
end
