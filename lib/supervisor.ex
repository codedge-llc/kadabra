defmodule Kadabra.Supervisor do
  @moduledoc false

  use Supervisor
  import Supervisor.Spec

  alias Kadabra.{ConnectionSupervisor, Stream}

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    supervise([], strategy: :one_for_one)
  end

  def start_connection(uri, pid, opts) do
    ConnectionSupervisor.start_link(uri, pid, opts)
  end
end
