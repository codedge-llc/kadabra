defmodule Kadabra.ConnectionPool do
  @moduledoc false

  defstruct connection: nil,
            pending_demand: 0,
            events: []

  @type t :: %__MODULE__{
          connection: pid,
          pending_demand: non_neg_integer,
          events: [any, ...]
        }

  require Logger

  alias Kadabra.Connection

  @spec start_link(URI.t(), pid, Keyword.t()) :: {:ok, pid}
  def start_link(uri, pid, opts) do
    config = %Kadabra.Config{
      client: pid,
      uri: uri,
      opts: opts
    }

    GenServer.start_link(__MODULE__, config)
  end

  def child_spec(opts) do
    uri = Keyword.get(opts, :uri)
    pid = Keyword.get(opts, :pid)
    opts = Keyword.get(opts, :opts)

    %{
      id: :erlang.make_ref(),
      restart: :transient,
      start: {__MODULE__, :start_link, [uri, pid, opts]},
      type: :worker
    }
  end

  def request(pid, requests) when is_list(requests) do
    GenServer.call(pid, {:request, requests})
  end

  def request(pid, request) do
    GenServer.call(pid, {:request, [request]})
  end

  def ping(pid), do: GenServer.call(pid, :ping)

  def close(pid), do: GenServer.call(pid, :close)

  ## Callbacks

  def init(config) do
    config = %{config | queue: self()}

    Process.flag(:trap_exit, true)

    {:ok, connection} = Connection.start_link(config)
    {:ok, %__MODULE__{connection: connection}}
  end

  def handle_cast({:ask, demand}, state) do
    state =
      state
      |> increment_demand(demand)
      |> dispatch_events()

    {:noreply, state}
  end

  def handle_call(:close, _from, state) do
    Connection.close(state.connection)
    {:stop, :shutdown, :ok, state}
  end

  def handle_call(:ping, _from, state) do
    Connection.ping(state.connection)
    {:reply, :ok, state}
  end

  def handle_call({:request, requests}, from, state) do
    GenServer.reply(from, :ok)

    state =
      state
      |> enqueue(requests)
      |> dispatch_events()

    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, :shutdown}, state) do
    {:stop, :shutdown, state}
  end

  def handle_info({:EXIT, _pid, {:shutdown, :connection_error}}, state) do
    {:stop, :shutdown, state}
  end

  def handle_info({:EXIT, _pid, {:ssl_error, _}}, state) do
    Logger.warning(
      'TLS client: In state connection received SERVER ALERT: Fatal - Certificate Expired'
    )

    {:noreply, state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  def terminate(_reason, _state) do
    :ok
  end

  ## Private

  defp increment_demand(state, demand) do
    state
    |> Map.put(:pending_demand, state.pending_demand + demand)
  end

  defp enqueue(state, requests) do
    state
    |> Map.put(:events, state.events ++ requests)
  end

  defp dispatch_events(state) do
    {to_dispatch, rest} = Enum.split(state.events, state.pending_demand)
    new_pending = state.pending_demand - Enum.count(to_dispatch)

    GenServer.cast(state.connection, {:request, to_dispatch})
    %{state | pending_demand: new_pending, events: rest}
  end
end
