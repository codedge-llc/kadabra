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

  def queue_request(pid, %{on_response: nil} = request) do
    queue_request(pid, %{request | on_response: &IO.inspect/1})
  end
  def queue_request(pid, request) do
    pid
    |> via_tuple()
    |> GenStage.call({:request, request})
  end

  def handle_call({:request, request}, from, {queue, pending_demand}) do
    GenStage.reply(from, :ok)
    queue = :queue.in(request, queue)
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
