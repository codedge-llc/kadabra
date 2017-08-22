defmodule Kadabra.Supervisor do
  @moduledoc false

  use Supervisor
  import Supervisor.Spec

  alias Kadabra.Stream

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    supervise([], strategy: :one_for_one)
  end

  def start_opts do
    [id: :erlang.make_ref, restart: :transient]
  end

  def start_encoder(ref) do
    start_hpack(ref, :encoder)
  end

  def start_stream(connection, settings, stream_id \\ nil) do
    stream = Stream.new(connection, settings, stream_id || connection.stream_id)
    spec = worker(Stream, [stream], start_opts())
    Supervisor.start_child(__MODULE__, spec)
  end

  def start_settings(ref) do
    spec = worker(Kadabra.ConnectionSettings, [ref], start_opts())
    Supervisor.start_child(__MODULE__, spec)
  end

  def start_decoder(ref) do
    start_hpack(ref, :decoder)
  end

  def start_hpack(ref, name) do
    spec = worker(Kadabra.Hpack, [{ref, name}], start_opts())
    Supervisor.start_child(__MODULE__, spec)
  end

  def pid_for(ref, name) do
    case Registry.lookup(Registry.Kadabra, via_tuple(ref, name)) do
      [{_self, pid}] -> pid
      [] -> nil
    end
  end

  def via_tuple(ref, name) do
    {:via, Registry, {Registry.Kadabra, {ref, name}}}
  end
end
