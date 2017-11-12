defmodule Kadabra.ConnectionSupervisor do
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

  def start_opts do
    [id: :erlang.make_ref, restart: :transient]
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

  def start_encoder(ref) do
    start_hpack(ref, :encoder)
  end

  def start_decoder(ref) do
    start_hpack(ref, :decoder)
  end

  def start_hpack(ref, name) do
    spec = worker(Hpack, [{ref, name}], start_opts())
    Supervisor.start_child(via_tuple(ref), spec)
  end

  def init({_uri, _pid, ref, _opts}) do
    children = [
      worker(Hpack, [{ref, :encoder}], start_opts()),
      worker(Hpack, [{ref, :decoder}], start_opts())
    ]

    supervise(children, strategy: :one_for_one)
  end
end
