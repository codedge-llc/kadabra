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

  def start_stream(%{flow_control: flow} = conn, stream_id \\ nil) do
    stream = Stream.new(conn, flow.settings, stream_id || flow.stream_id)
    spec = worker(Stream, [stream], start_opts())
    Supervisor.start_child(__MODULE__, spec)
  end

  def start_encoder(ref) do
    start_hpack(ref, :encoder)
  end

  def start_decoder(ref) do
    start_hpack(ref, :decoder)
  end

  def start_hpack(ref, name) do
    spec = worker(Kadabra.Hpack, [{ref, name}], start_opts())
    Supervisor.start_child(__MODULE__, spec)
  end
end
