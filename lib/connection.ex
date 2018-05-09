defmodule Kadabra.Connection do
  @moduledoc false

  defstruct buffer: "",
            config: nil,
            flow_control: nil,
            remote_window: 65_535,
            queue: nil

  use GenStage
  require Logger

  import Kernel, except: [send: 2]

  alias Kadabra.{
    Config,
    Connection,
    ConnectionQueue,
    Encodable,
    Error,
    Frame,
    Socket
  }

  alias Kadabra.Frame.{Goaway, Ping}

  alias Kadabra.Connection.{FlowControl, Processor}

  @type t :: %__MODULE__{
          buffer: binary,
          config: term,
          flow_control: term,
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

  def init(%Config{supervisor: sup} = config) do
    state = initial_state(config)
    Kernel.send(self(), :start)
    {:consumer, state, subscribe_to: [ConnectionQueue.via_tuple(sup)]}
  end

  defp initial_state(%Config{opts: opts} = config) do
    settings = Keyword.get(opts, :settings, Connection.Settings.fastest())
    socket = config.supervisor |> Socket.via_tuple()

    %__MODULE__{
      config: %{config | socket: socket},
      flow_control: %Connection.FlowControl{
        settings: settings
      }
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

    bin = flow.stream_id |> Goaway.new() |> Encodable.to_bin()
    Socket.send(config.socket, bin)

    Kernel.send(config.client, {:closed, config.supervisor})

    Task.Supervisor.start_child(Kadabra.Tasks, fn ->
      Kadabra.Supervisor.stop(config.supervisor)
    end)

    {:stop, :normal, :ok, state}
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

  def handle_info(:start, %{config: config, flow_control: flow} = state) do
    config.supervisor
    |> Socket.via_tuple()
    |> Socket.set_active()

    bin =
      %Frame.Settings{settings: flow.settings}
      |> Encodable.to_bin()

    config.supervisor
    |> Socket.via_tuple()
    |> Socket.send(bin)

    {:noreply, [], state}
  end

  def handle_info({:closed, _pid}, %{config: config} = state) do
    Kernel.send(config.client, {:closed, config.supervisor})
    Task.start(fn -> Kadabra.Supervisor.stop(config.supervisor) end)

    {:stop, :normal, state}
  end

  def handle_info({:finished, stream_id}, %{flow_control: flow} = state) do
    flow =
      flow
      |> FlowControl.decrement_active_stream_count()
      |> FlowControl.remove_active(stream_id)
      |> FlowControl.process(state.config)

    GenStage.ask(state.queue, 1)

    {:noreply, [], %{state | flow_control: flow}}
  end

  def handle_info({:push_promise, stream}, %{config: config} = state) do
    Kernel.send(config.client, {:push_promise, stream})
    {:noreply, [], state}
  end

  def handle_info({:recv, frame}, state) do
    case Processor.process(frame, %{config: config} = state) do
      {:ok, state} ->
        {:noreply, [], state}

      {:connection_error, error, state} ->
        code = Error.code(error)

        bin =
          state.flow_control.stream_id
          |> Goaway.new(code)
          |> Encodable.to_bin()

        Socket.send(config.socket, bin)
        {:stop, :normal, state}
    end
  end

  def send_protocol_error(state) do
    send_goaway(state, :PROTOCOL_ERROR)
  end

  def send_frame_size_error(state) do
    send_goaway(state, :FRAME_SIZE_ERROR)
  end

  def send_goaway(%{config: config, flow_control: flow}, error) do
    bin =
      flow.stream_id
      |> Frame.Goaway.new(Error.code(error))
      |> Encodable.to_bin()

    Socket.send(config.socket, bin)
  end
end
