defmodule Kadabra.ConnectionQueue do
  @moduledoc false

  use GenStage

  def start_link(sup) do
    name = via_tuple(sup)
    GenStage.start_link(__MODULE__, :ok, name: name)
  end

  def via_tuple(ref) do
    {:via, Registry, {Registry.Kadabra, {ref, __MODULE__}}}
  end

  def init(:ok) do
    {:producer, {:queue.new, 0}, dispatcher: GenStage.BroadcastDispatcher}
  end

  def handle_call({:send, :headers, headers}, from, {queue, pending_demand}) do
    GenStage.reply(from, :ok)
    queue = :queue.in({:send, :headers, headers, nil}, queue)
    dispatch_events(queue, pending_demand, [])
  end
  def handle_call({:send, :headers, headers, payload}, from, {queue, pending_demand}) do
    GenStage.reply(from, :ok)
    queue = :queue.in({:send, :headers, headers, payload}, queue)
    dispatch_events(queue, pending_demand, [])
  end

  def handle_demand(incoming_demand, {queue, pending_demand}) do
    dispatch_events(queue, incoming_demand + pending_demand, [])
  end

  defp dispatch_events(queue, 0, events) do
    {:noreply, Enum.reverse(events), {queue, 0}}
  end
  defp dispatch_events(queue, demand, events) do
    case :queue.out(queue) do
      {{:value, event}, queue} ->
        dispatch_events(queue, demand - 1, [event | events])
      {:empty, queue} ->
        {:noreply, Enum.reverse(events), {queue, demand}}
    end
  end
end
