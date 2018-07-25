defmodule Kadabra.Application do
  @moduledoc false

  use Application
  import Supervisor.Spec

  alias Kadabra.ConnectionPool

  @app :kadabra

  def start(_type, _args) do
    children = [
      supervisor(Registry, [:unique, Registry.Kadabra]),
      supervisor(Task.Supervisor, [[name: Kadabra.Tasks]])
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: @app)
  end

  def start_connection(uri, pid, opts) do
    Supervisor.start_child(
      @app,
      worker(Kadabra.ConnectionPool, [uri, pid, opts], spec_opts())
    )
  end

  defp spec_opts do
    ref = :erlang.make_ref()
    [id: ref, restart: :transient]
  end

  def ping(pid) do
    ConnectionPool.ping(pid)
  end

  def close(pid) do
    ConnectionPool.close(pid)
  end
end
