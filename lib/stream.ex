defmodule Kadabra.Stream do
  @moduledoc false

  defstruct id: nil,
            flow: nil,
            headers: [],
            body: "",
            state: @idle,
            on_response: nil

  require Logger

  alias Kadabra.{Connection, Encodable, Hpack, Http2, Stream}
  alias Kadabra.Connection.{Settings, Socket}

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
          state: atom,
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

  def new(%Settings{} = settings, stream_id) do
    flow_opts = [
      stream_id: stream_id,
      window: settings.initial_window_size,
      max_frame_size: settings.max_frame_size
    ]

    %__MODULE__{
      id: stream_id,
      flow: Stream.FlowControl.new(flow_opts),
      state: @idle
    }
  end

  def start_link(%{id: id, ref: ref} = stream) do
    :gen_statem.start_link(via_tuple(ref, id), __MODULE__, stream, [])
  end

  def via_tuple(ref, stream_id) do
    {:via, Registry, {Registry.Kadabra, {ref, stream_id}}}
  end

  def close(ref, stream_id) do
    ref |> via_tuple(stream_id) |> cast_recv(:close)
  end

  def cast_recv(pid, frame) do
    :gen_statem.cast(pid, {:recv, frame})
  end

  def call_recv(pid, frame) do
    :gen_statem.call(pid, {:recv, frame})
  end

  def cast_send(pid, frame) do
    :gen_statem.cast(pid, {:send, frame})
  end

  def recv(:close, _state, _stream) do
    {:stop, :normal}
  end

  # For SETTINGS initial_window_size and max_frame_size changes
  def recv({:settings_change, window, new_max_frame}, _state, stream) do
    flow =
      stream.flow
      |> Stream.FlowControl.increment_window(window)
      |> Stream.FlowControl.set_max_frame_size(new_max_frame)

    {:keep_state, %{stream | flow: flow}}
  end

  def recv(%{state: @hc_local} = stream, %Data{end_stream: true, data: data}) do
    %Stream{stream | body: stream.body <> data, state: @closed}
  end

  def recv(stream, %Data{end_stream: true, data: data}) do
    %Stream{stream | body: stream.body <> data, state: @hc_remote}
  end

  def recv(stream, %Data{end_stream: false, data: data}) do
    %Stream{stream | body: stream.body <> data}
  end

  def recv(stream, %RstStream{} = _frame) do
    if stream.state in [@open, @hc_local, @hc_remote, @closed] do
      %{stream | state: @closed}
    else
      stream
    end

    # IO.inspect(frame, label: "Got RST_STREAM")
  end

  # Headers, PushPromise and Continuation frames must be calls
  #
  def recv(stream, %WindowUpdate{window_size_increment: inc}, conn) do
    flow =
      stream.flow
      |> Stream.FlowControl.increment_window(inc)
      |> Stream.FlowControl.process(conn.socket)

    %{stream | flow: flow}
  end

  def recv(stream, %Headers{end_stream: true} = frame, conn) do
    {:ok, headers} = Hpack.decode(conn.ref, frame.header_block_fragment)
    %Stream{stream | headers: stream.headers ++ headers, state: @hc_remote}
  end

  def recv(stream, %Headers{end_stream: false} = frame, conn) do
    {:ok, headers} = Hpack.decode(conn.ref, frame.header_block_fragment)
    %Stream{stream | headers: stream.headers ++ headers}
  end

  def recv(%{state: @idle} = stream, %PushPromise{} = frame, conn) do
    {:ok, headers} = Hpack.decode(conn.ref, frame.header_block_fragment)

    %Stream{
      stream
      | headers: stream.headers ++ headers,
        state: @reserved_remote
    }
  end

  def recv(stream, %Continuation{} = frame, conn) do
    {:ok, headers} = Hpack.decode(conn.ref, frame.header_block_fragment)
    %Stream{stream | headers: stream.headers ++ headers}
  end

  def recv(stream, frame, conn) do
    """
    Unknown RECV on stream #{stream.id}
    Stream: #{inspect(stream)}
    Frame: #{inspect(frame)}
    Conn: #{inspect(conn)}
    """
    |> Logger.info()

    stream
  end

  # Enter Events

  def handle_event(:enter, _old, @hc_remote, stream) do
    bin = stream.id |> RstStream.new() |> Encodable.to_bin()
    Socket.send(stream.socket, bin)

    :gen_statem.cast(self(), :close)
    {:keep_state, stream}
  end

  def handle_event(:enter, _old, @closed, stream) do
    response = Response.new(stream)
    Kadabra.Tasks.run(stream.on_response, response)
    send(stream.connection, {:finished, response})

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

  # def handle_event({:call, from}, {:recv, frame}, state, stream) do
  #  recv(stream, frame, state, stream)
  # end

  def handle_event({:call, from}, {:send_headers, request}, _state, stream) do
    %{headers: headers, body: payload, on_response: on_resp} = request

    headers = add_headers(headers, stream)

    {:ok, encoded} = Hpack.encode(stream.ref, headers)
    headers_payload = :erlang.iolist_to_binary(encoded)

    flags = if payload, do: 0x4, else: 0x5
    h = Http2.build_frame(@headers, flags, stream.id, headers_payload)
    Socket.send(stream.socket, h)
    # Logger.info("Sending, Stream ID: #{stream.id}, size: #{byte_size(h)}")

    # Reply early for better performance
    :gen_statem.reply(from, :ok)

    flow =
      if payload do
        stream.flow
        |> Stream.FlowControl.add(payload)
        |> Stream.FlowControl.process(stream.socket)
      else
        stream.flow
      end

    stream = %{stream | flow: flow, on_response: on_resp}

    {:next_state, @open, stream, []}
  end

  def add_headers(headers, uri) do
    h =
      headers ++
        [
          {":scheme", uri.scheme},
          {":authority", uri.authority}
        ]

    # sorting headers to have pseudo headers first.
    Enum.sort(h, fn {a, _b}, {c, _d} -> a < c end)
  end

  def send_frame(stream, request, conn) do
    %{headers: headers, body: payload, on_response: on_resp} = request

    headers = add_headers(headers, conn.uri)

    {:ok, encoded} = Hpack.encode(conn.ref, headers)
    headers_payload = :erlang.iolist_to_binary(encoded)

    flags = if payload, do: 0x4, else: 0x5
    h = Http2.build_frame(@headers, flags, stream.id, headers_payload)
    Socket.send(conn.socket, h)
    # Logger.info("Sending, Stream ID: #{stream.id}, size: #{byte_size(h)}")

    flow =
      if payload do
        stream.flow
        |> Stream.FlowControl.add(payload)
        |> Stream.FlowControl.process(conn.socket)
      else
        stream.flow
      end

    %{stream | flow: flow, on_response: on_resp, state: @open}
  end

  # Other Callbacks

  def init(stream), do: {:ok, @idle, stream}

  def callback_mode, do: [:handle_event_function, :state_enter]

  def terminate(_reason, _state, _data), do: :void

  def code_change(_vsn, state, data, _extra), do: {:ok, state, data}
end
