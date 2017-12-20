defmodule Kadabra.Supervisor do
  @moduledoc false

  use Supervisor
  import Supervisor.Spec

  alias Kadabra.{ConnectionSupervisor, StreamSupervisor}

  def start_link(uri, pid, opts) do
    ref = :erlang.make_ref
    Supervisor.start_link(__MODULE__, {uri, pid, ref, opts})
  end

  def init({uri, pid, ref, opts}) do
    children = [
      supervisor(StreamSupervisor, [ref], id: :stream_sup),
      supervisor(ConnectionSupervisor, [uri, pid, self(), ref, opts], id: :connection_sup)
    ]

    supervise(children, strategy: :one_for_one)
  end
end
