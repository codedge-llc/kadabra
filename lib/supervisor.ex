defmodule Kadabra.Supervisor do
  @moduledoc false

  use Supervisor

  alias Kadabra.{Connection, ConnectionQueue}

  def start_link(uri, pid, opts) do
    config = %Kadabra.Config{
      ref: :erlang.make_ref(),
      client: pid,
      uri: uri,
      opts: opts
    }

    Supervisor.start_link(__MODULE__, config)
  end

  def worker_opts(id) do
    [id: id, restart: :permanent]
  end

  def init(%Kadabra.Config{} = config) do
    Process.flag(:trap_exit, true)

    config =
      config
      |> Map.put(:supervisor, self())
      |> Map.put(:queue, ConnectionQueue.via_tuple(self()))

    children = [
      worker(ConnectionQueue, [self()], worker_opts(:connection_queue)),
      worker(Connection, [config], worker_opts(:connection))
    ]

    # If anything crashes, something really bad happened
    supervise(children, strategy: :one_for_all, max_restarts: 0)
  end
end
