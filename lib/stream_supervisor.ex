defmodule Kadabra.StreamSupervisor do
  @moduledoc false

  use Supervisor
  import Supervisor.Spec

  alias Kadabra.Stream

  def start_link(ref) do
    name = via_tuple(ref)
    Supervisor.start_link(__MODULE__, :ok, name: name)
  end

  def via_tuple(ref) do
    {:via, Registry, {Registry.Kadabra, {ref, __MODULE__}}}
  end

  def start_opts(id \\ :erlang.make_ref()) do
    [id: id, restart: :transient]
  end

  def start_stream(%{flow_control: flow, ref: ref} = conn, stream_id \\ nil) do
    stream = Stream.new(conn, flow.settings, stream_id || flow.stream_id)
    spec = worker(Stream, [stream], start_opts())
    Supervisor.start_child(via_tuple(ref), spec)
  end

  def init(:ok) do
    supervise([], strategy: :one_for_all)
  end
end
