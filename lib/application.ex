defmodule Kadabra.Application do
  @moduledoc false

  use Application
  import Supervisor.Spec

  alias Kadabra.ConnectionPool

  def start(_type, _args) do
    children = [
      supervisor(Registry, [:unique, Registry.Kadabra]),
      supervisor(Task.Supervisor, [[name: Kadabra.Tasks]])
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: :kadabra)
  end

  def route_request(pid, request) when is_pid(pid) do
    ConnectionPool.request(pid, request)
  end

  def route_request(uri, request) do
    pid =
      case open(uri, name: via_tuple(uri)) do
        {:ok, pid} -> pid
        {:error, {{:already_started, pid}, _}} -> pid
      end

    ConnectionPool.request(pid, request)
  end

  defp via_tuple(%{scheme: scheme, host: host, port: port}) do
    {:via, Registry, {Registry.Kadabra, {scheme, host, port}}}
  end

  def open(uri, opts) do
    spec_opts = [id: :erlang.make_ref(), restart: :transient]
    spec = worker(Kadabra.ConnectionPool, [uri, self(), opts], spec_opts)

    Supervisor.start_child(:kadabra, spec)
  end
end
