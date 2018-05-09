defmodule Kadabra.Stream do
  @moduledoc false

  defstruct id: nil,
            body: "",
            config: nil,
            connection: nil,
            settings: nil,
            flow: nil,
            headers: [],
            on_push_promise: nil,
            on_response: nil

  require Logger

  alias Kadabra.{Config, Encodable, Frame, Hpack, Socket, Stream, Tasks}
  alias Kadabra.Connection.Settings

  alias Kadabra.Frame.{
    Continuation,
    Data,
    Headers,
    PushPromise,
    RstStream,
    WindowUpdate
  }

  alias Kadabra.Stream.Response

  @type t :: %__MODULE__{
          id: pos_integer,
          config: term,
          connection: pid,
          settings: pid,
          flow: Kadabra.Stream.FlowControl.t(),
          headers: [...],
          body: binary
        }

  # @data 0x0
  @headers 0x1

  @closed :closed
  @hc_local :half_closed_local
  @hc_remote :half_closed_remote
  @idle :idle
  @open :open
  # @reserved_local :reserved_local
  @reserved_remote :reserved_remote

  def new(%Config{} = config, %Settings{} = settings, stream_id) do
    flow_opts = [
      stream_id: stream_id,
      socket: config.socket,
      window: settings.initial_window_size,
      max_frame_size: settings.max_frame_size
    ]

    %__MODULE__{
      id: stream_id,
      config: config,
      connection: self(),
      flow: Stream.FlowControl.new(flow_opts)
    }
  end

  def start_link(%{id: id, config: config} = stream) do
    config.ref
    |> via_tuple(id)
    |> :gen_statem.start_link(__MODULE__, stream, [])
  end

  def via_tuple(ref, stream_id) do
    {:via, Registry, {Registry.Kadabra, {ref, stream_id}}}
  end

  def close(ref, stream_id) do
    ref |> via_tuple(stream_id) |> call_recv(:close)
  end

  def call_recv(pid, frame) do
    :gen_statem.call(pid, {:recv, frame})
  end

  def cast_send(pid, frame) do
    :gen_statem.cast(pid, {:send, frame})
  end

  # recv

  def recv(from, :close, _state, _stream) do
    {:stop, :normal, [{:reply, from, :ok}]}
  end

  # For SETTINGS initial_window_size and max_frame_size changes
  def recv(from, {:settings_change, window, new_max_frame}, _state, stream) do
    flow =
      stream.flow
      |> Stream.FlowControl.increment_window(window)
      |> Stream.FlowControl.set_max_frame_size(new_max_frame)

    {:keep_state, %{stream | flow: flow}, [{:reply, from, :ok}]}
  end

  def recv(from, %WindowUpdate{window_size_increment: inc}, _state, stream) do
    flow =
      stream.flow
      |> Stream.FlowControl.increment_window(inc)
      |> Stream.FlowControl.process()

    {:keep_state, %{stream | flow: flow}, [{:reply, from, :ok}]}
  end

  def recv(from, %Data{end_stream: true, data: data}, state, stream)
      when state in [@hc_local] do
    :gen_statem.reply(from, :ok)
    stream = %Stream{stream | body: stream.body <> data}
    {:next_state, @closed, stream}
  end

  def recv(from, %Data{end_stream: true, data: data}, _state, stream) do
    :gen_statem.reply(from, :ok)
    stream = %Stream{stream | body: stream.body <> data}
    {:next_state, @hc_remote, stream}
  end

  def recv(from, %Data{end_stream: false, data: data}, _state, stream) do
    :gen_statem.reply(from, :ok)
    stream = %Stream{stream | body: stream.body <> data}
    {:keep_state, stream}
  end

  def recv(from, %Headers{end_stream: end_stream?} = frame, _state, stream) do
    case Hpack.decode(stream.config.ref, frame.header_block_fragment) do
      {:ok, headers} ->
        :gen_statem.reply(from, :ok)

        stream = %Stream{stream | headers: stream.headers ++ headers}

        if end_stream?,
          do: {:next_state, @hc_remote, stream},
          else: {:keep_state, stream}

      _error ->
        :gen_statem.reply(from, {:connection_error, :COMPRESSION_ERROR})
        {:stop, :normal}
    end
  end

  def recv(from, %RstStream{} = _frame, state, stream)
      when state in [@open, @hc_local, @hc_remote, @closed] do
    # IO.inspect(frame, label: "Got RST_STREAM")
    {:next_state, :closed, stream, [{:reply, from, :ok}]}
  end

  def recv(from, %PushPromise{} = frame, state, %{config: config} = stream)
      when state in [@idle] do
    {:ok, headers} = Hpack.decode(config.ref, frame.header_block_fragment)

    stream = %Stream{stream | headers: stream.headers ++ headers}

    :gen_statem.reply(from, :ok)

    response = Response.new(stream.id, stream.headers, stream.body)
    send(stream.connection, {:push_promise, response})
    {:next_state, @reserved_remote, stream}
  end

  def recv(from, %Continuation{} = frame, _state, %{config: config} = stream) do
    {:ok, headers} = Hpack.decode(config.ref, frame.header_block_fragment)

    :gen_statem.reply(from, :ok)

    stream = %Stream{stream | headers: stream.headers ++ headers}
    {:keep_state, stream}
  end

  def recv(frame, state, stream) do
    """
    Unknown RECV on stream #{stream.id}
    Frame: #{inspect(frame)}
    State: #{inspect(state)}
    """
    |> Logger.info()

    {:keep_state, stream}
  end

  # Enter Events

  def handle_event(:enter, _old, @hc_remote, %{config: config} = stream) do
    bin = stream.id |> RstStream.new() |> Encodable.to_bin()
    Socket.send(config.socket, bin)

    :gen_statem.cast(self(), :close)
    {:keep_state, stream}
  end

  def handle_event(:enter, _old, @closed, stream) do
    response = Response.new(stream.id, stream.headers, stream.body)
    Tasks.run(stream.on_response, response)
    send(stream.connection, {:finished, stream.id})
    send(stream.config.client, {:end_stream, response})

    {:stop, :normal}
  end

  def handle_event(:enter, _old, _new, stream), do: {:keep_state, stream}

  # Casts

  def handle_event(:cast, :close, _state, stream) do
    {:next_state, @closed, stream}
  end

  def handle_event(:cast, {:recv, frame}, state, stream) do
    recv(frame, state, stream)
  end

  def handle_event(:cast, msg, state, stream) do
    """
    === Unknown cast ===
    #{inspect(msg)}
    State: #{inspect(state)}
    Stream: #{inspect(stream)}
    """
    |> Logger.info()

    {:keep_state, stream}
  end

  # Calls

  def handle_event({:call, from}, {:recv, frame}, state, stream) do
    recv(from, frame, state, stream)
  end

  def handle_event({:call, from}, {:send_headers, request}, _state, stream) do
    %{headers: headers, body: payload, on_response: on_resp} = request

    headers = add_headers(headers, stream.config)

    {:ok, encoded} = Hpack.encode(stream.config.ref, headers)
    headers_payload = :erlang.iolist_to_binary(encoded)

    flags = if payload, do: 0x4, else: 0x5
    h = Frame.binary_frame(@headers, flags, stream.id, headers_payload)
    Socket.send(stream.config.socket, h)
    # Logger.info("Sending, Stream ID: #{stream.id}, size: #{byte_size(h)}")

    # Reply early for better performance
    :gen_statem.reply(from, :ok)

    flow =
      if payload do
        stream.flow
        |> Stream.FlowControl.add(payload)
        |> Stream.FlowControl.process()
      else
        stream.flow
      end

    stream = %{stream | flow: flow, on_response: on_resp}

    {:next_state, @open, stream}
  end

  def add_headers(headers, %{uri: uri}) do
    h =
      headers ++
        [
          {":scheme", uri.scheme},
          {":authority", uri.authority}
        ]

    # sorting headers to have pseudo headers first.
    Enum.sort(h, fn {a, _b}, {c, _d} -> a < c end)
  end

  # Other Callbacks

  def init(stream), do: {:ok, @idle, stream}

  def callback_mode, do: [:handle_event_function, :state_enter]

  def terminate(_reason, _state, _data), do: :void

  def code_change(_vsn, state, data, _extra), do: {:ok, state, data}
end
