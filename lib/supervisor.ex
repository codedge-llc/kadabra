defmodule Kadabra.Supervisor do
  @moduledoc false

  use Supervisor
  import Supervisor.Spec

  alias Kadabra.{Connection, Hpack, StreamSupervisor}

  def start_link(uri, pid, opts) do
    ref = :erlang.make_ref
    Supervisor.start_link(__MODULE__, {uri, pid, ref, opts})
  end

  def start_opts(id \\ :erlang.make_ref()) do
    [id: id, restart: :transient]
  end

  def init({uri, pid, ref, opts}) do
    children = [
      supervisor(StreamSupervisor, [ref], id: :stream_sup),
      worker(Hpack, [{ref, :encoder}], start_opts(:encoder)),
      worker(Hpack, [{ref, :decoder}], start_opts(:decoder)),
      worker(Connection, [uri, pid, self(), ref, opts], start_opts(:connection))
    ]

    supervise(children, strategy: :one_for_all)
  end
end
