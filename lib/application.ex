defmodule Kadabra.Application do
  @moduledoc false

  use Application
  import Supervisor.Spec

  alias Kadabra.Connection

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
      supervisor(Kadabra.Supervisor, [uri, pid, opts], spec_opts())
    )
  end

  defp spec_opts do
    ref = :erlang.make_ref()
    [id: ref, restart: :temporary]
  end

  def ping(pid) do
    pid
    |> Connection.via_tuple()
    |> Connection.ping()
  end

  def close(pid) do
    pid
    |> Connection.via_tuple()
    |> Connection.close()
  end
end
