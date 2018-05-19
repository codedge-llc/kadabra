defmodule Kadabra.Supervisor do
  @moduledoc false

  use Supervisor

  alias Kadabra.{Connection, ConnectionQueue, Hpack, Socket, StreamSupervisor}

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

  def init(%Kadabra.Config{ref: ref} = config) do
    Process.flag(:trap_exit, true)

    config =
      config
      |> Map.put(:supervisor, self())
      |> Map.put(:queue, ConnectionQueue.via_tuple(self()))

    children = [
      supervisor(StreamSupervisor, [ref], worker_opts(:stream_supervisor)),
      worker(ConnectionQueue, [self()], worker_opts(:connection_queue)),
      worker(Socket, [config], worker_opts(:socket)),
      worker(Hpack, [ref, :encoder], worker_opts(:encoder)),
      worker(Hpack, [ref, :decoder], worker_opts(:decoder)),
      worker(Connection, [config], worker_opts(:connection))
    ]

    # If anything crashes, something really bad happened
    supervise(children, strategy: :one_for_all, max_restarts: 0)
  end
end
