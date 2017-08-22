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

	def start_encoder(ref) do
    start_hpack(ref, :encoder)
	end

  def start_stream(connection, settings) do
    stream = Stream.new(connection, settings, connection.stream_id)
    spec = worker(Stream, [stream], id: :erlang.make_ref, restart: :transient)
		case Supervisor.start_child(__MODULE__, spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> {:error, :process_already_exists}
      other -> other
    end
  end

  def start_settings(ref) do
    spec = worker(Kadabra.ConnectionSettings, [ref], id: :erlang.make_ref, restart: :transient)
		case Supervisor.start_child(__MODULE__, spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> {:error, :process_already_exists}
      other -> other
    end
  end

	def start_decoder(ref) do
    start_hpack(ref, :decoder)
	end

  def start_hpack(ref, name) do
    spec = worker(
      Kadabra.Hpack,
      [{ref, name}],
      id: :erlang.make_ref, restart: :transient
    )
		case Supervisor.start_child(__MODULE__, spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> {:error, :process_already_exists}
      other -> other
    end
  end

  def pid_for(ref, name) do
    Registry.lookup(Registry.Kadabra, via_tuple(ref, name)) |> IO.inspect(label: "pid_for")
    case Registry.lookup(Registry.Kadabra, via_tuple(ref, name)) do
      [{_self, pid}] -> pid
      [] -> nil 
    end
  end

  def via_tuple(ref, name) do
    {:via, Registry, {Registry.Kadabra, {ref, name}}}
  end
end
