defmodule Kadabra.ConnectionSupervisor do
  @moduledoc false

  use Supervisor
  import Supervisor.Spec

  alias Kadabra.{Connection, Hpack, Stream}

  def start_link(uri, pid, opts) do
    ref = :erlang.make_ref
    name = via_tuple(ref)
    Supervisor.start_link(__MODULE__, {uri, pid, ref, opts}, name: name)
    start_connection(uri, pid, ref, opts)
  end

  def via_tuple(ref) do
    {:via, Registry, {Registry.Kadabra, {ref, __MODULE__}}}
  end

  def start_opts(id \\ :erlang.make_ref) do
    [id: id, restart: :transient]
  end

  def start_connection(uri, pid, ref, opts) do
    spec = worker(Connection, [uri, pid, ref, opts])
    Supervisor.start_child(via_tuple(ref), spec)
  end

  def start_stream(%{flow_control: flow, ref: ref} = conn, stream_id \\ nil) do
    stream = Stream.new(conn, flow.settings, stream_id || flow.stream_id)
    spec = worker(Stream, [stream], start_opts())
    Supervisor.start_child(via_tuple(ref), spec)
  end

  def init({_uri, _pid, ref, _opts}) do
    children = [
      worker(Hpack, [{ref, :encoder}], start_opts(:encoder)),
      worker(Hpack, [{ref, :decoder}], start_opts(:decoder))
    ]

    supervise(children, strategy: :one_for_one)
  end
end
