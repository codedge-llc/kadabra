defmodule Kadabra.Connection do
  @moduledoc false

  defstruct buffer: "",
            config: nil,
            flow_control: nil,
            remote_window: 65_535,
            remote_settings: nil,
            local_settings: nil,
            queue: nil

  use GenStage
  require Logger

  import Kernel, except: [send: 2]

  alias Kadabra.{
    Config,
    Connection,
    Encodable,
    Error,
    Frame,
    Socket,
    StreamSupervisor
  }

  alias Kadabra.Frame.{Goaway, Ping}

  alias Kadabra.Connection.{FlowControl, Processor}

  @type t :: %__MODULE__{
          buffer: binary,
          config: term,
          flow_control: term,
          local_settings: Connection.Settings.t(),
          queue: pid
        }

  @type sock :: {:sslsocket, any, pid | {any, any}}

  def start_link(%Config{supervisor: sup} = config) do
    name = via_tuple(sup)
    GenStage.start_link(__MODULE__, config, name: name)
  end

  def via_tuple(ref) do
    {:via, Registry, {Registry.Kadabra, {ref, __MODULE__}}}
  end

  def init(%Config{queue: queue} = config) do
    state = initial_state(config)
    Kernel.send(self(), :start)
    Process.flag(:trap_exit, true)

    {:consumer, state, subscribe_to: [queue]}
  end

  defp initial_state(%Config{opts: opts, queue: queue} = config) do
    settings = Keyword.get(opts, :settings, Connection.Settings.fastest())
    socket = config.supervisor |> Socket.via_tuple()

    %__MODULE__{
      config: %{config | socket: socket},
      queue: queue,
      local_settings: settings,
      flow_control: %FlowControl{}
    }
  end

  def close(pid) do
    GenStage.call(pid, :close)
  end

  def ping(pid) do
    GenStage.cast(pid, {:send, :ping})
  end

  # handle_cast

  def handle_cast({:send, type}, state) do
    sendf(type, state)
  end

  def handle_cast(_msg, state) do
    {:noreply, [], state}
  end

  def handle_events(events, _from, state) do
    state = do_send_headers(events, state)
    {:noreply, [], state}
  end

  def handle_subscribe(:producer, _opts, from, state) do
    {:manual, %{state | queue: from}}
  end

  # handle_call

  def handle_call(:close, _from, %Connection{} = state) do
    %Connection{
      flow_control: flow,
      config: config
    } = state

    StreamSupervisor.stop(state.config.ref)

    bin = flow.stream_set.stream_id |> Goaway.new() |> Encodable.to_bin()
    Socket.send(config.socket, bin)

    {:stop, :shutdown, :ok, state}
  end

  # sendf

  @spec sendf(:goaway | :ping, t) :: {:noreply, [], t}
  def sendf(:ping, %Connection{config: config} = state) do
    bin = Ping.new() |> Encodable.to_bin()
    Socket.send(config.socket, bin)
    {:noreply, [], state}
  end

  def sendf(_else, state) do
    {:noreply, [], state}
  end

  defp do_send_headers(request, %{flow_control: flow} = state) do
    flow =
      flow
      |> FlowControl.add(request)
      |> FlowControl.process(state.config)

    %{state | flow_control: flow}
  end

  def handle_info(:start, %{config: config} = state) do
    config.supervisor
    |> Socket.via_tuple()
    |> Socket.set_active()

    bin =
      %Frame.Settings{settings: state.local_settings}
      |> Encodable.to_bin()

    config.supervisor
    |> Socket.via_tuple()
    |> Socket.send(bin)

    {:noreply, [], state}
  end

  def handle_info({:closed, _pid}, state) do
    {:stop, :shutdown, state}
  end

  def handle_info({:DOWN, _, _, _pid, {:shutdown, {:finished, sid}}}, state) do
    GenStage.ask(state.queue, 1)

    flow =
      state.flow_control
      |> FlowControl.finish_stream(sid)
      |> FlowControl.process(state.config)

    {:noreply, [], %{state | flow_control: flow}}
  end

  def handle_info({:push_promise, stream}, %{config: config} = state) do
    Kernel.send(config.client, {:push_promise, stream})
    {:noreply, [], state}
  end

  def handle_info({:recv, frame}, state) do
    case Processor.process(frame, state) do
      {:ok, state} ->
        {:noreply, [], state}

      {:connection_error, error, reason, state} ->
        handle_connection_error(state, error, reason)
        {:stop, {:shutdown, :connection_error}, state}
    end
  end

  defp handle_connection_error(%{config: config} = state, error, reason) do
    code = <<Error.code(error)::32>>

    bin =
      state.flow_control.stream_set.stream_id
      |> Goaway.new(code, reason)
      |> Encodable.to_bin()

    Socket.send(config.socket, bin)
  end

  def terminate(_reason, %{config: config}) do
    Kernel.send(config.client, {:closed, config.supervisor})
    :ok
  end
end
