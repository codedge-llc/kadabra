defmodule Kadabra.Stream do
  @moduledoc false

  defstruct id: nil,
            uri: nil,
            connection: nil,
            encoder: nil,
            decoder: nil,
            settings: nil,
            socket: nil,
            flow_control: nil,
            flow: nil,
            headers: [],
            body: "",
            buffer: "",
            window: 1_048_576,
            scheme: :https

  require Logger

  alias Kadabra.{Connection, Encodable, Hpack, Http2, Stream}
  alias Kadabra.Frame.{Continuation, Data, Headers, PushPromise, RstStream,
    WindowUpdate}

  @type t :: %__MODULE__{
    id: pos_integer,
    uri: charlist,
    connection: pid,
    encoder: pid,
    decoder: pid,
    settings: pid,
    socket: pid,
    flow_control: pid,
    flow: Kadabra.Stream.FlowControl.t,
    headers: [...],
    body: binary,
    scheme: :https
  }

  @data 0x0
  @headers 0x1

  @closed :closed
  @half_closed_local :half_closed_local
  @half_closed_remote :half_closed_remote
  @idle :idle
  @open :open
  # @reserved_local :reserved_local
  @reserved_remote :reserved_remote

  def new(%Connection{} = conn) do
    %__MODULE__{
      id: conn.stream_id,
      uri: conn.uri,
      connection: self(),
      socket: conn.socket,
      settings: conn.settings,
      encoder: conn.encoder_state,
      decoder: conn.decoder_state,
      buffer: "",
      window: 1_048_576,
      flow_control: conn.flow_control,
      flow: Stream.FlowControl.new(conn.stream_id)
    }
  end
  def new(%Connection{} = conn, stream_id) do
    conn
    |> new()
    |> Map.put(:id, stream_id)
  end

  def start_link(stream) do
    :gen_statem.start_link(__MODULE__, stream, [])
  end

  def cast_recv(pid, frame) do
    :gen_statem.cast(pid, {:recv, frame})
  end

  def cast_send(pid, frame) do
    :gen_statem.cast(pid, {:send, frame})
  end

  def recv(%Data{end_stream: true, data: data}, _state, stream) do
    stream = %Stream{stream | body: stream.body <> data}
    {:next_state, @half_closed_remote, stream}
  end
  def recv(%Data{end_stream: false, data: data}, _state, stream) do
    stream = %Stream{stream | body: stream.body <> data}
    # IO.puts("got data frame")
    {:keep_state, stream}
  end

  def recv(%Headers{header_block_fragment: fragment,
                    end_stream: true}, _state, stream) do

    {:ok, headers} = Hpack.decode(stream.decoder, fragment)
    stream = %Stream{stream | headers: stream.headers ++ headers}
    {:next_state, @half_closed_remote, stream}
  end
  def recv(%Headers{header_block_fragment: fragment,
                    end_stream: false}, _state, stream) do

    {:ok, headers} = Hpack.decode(stream.decoder, fragment)
    stream = %Stream{stream | headers: stream.headers ++ headers}
    {:keep_state, stream}
  end

  def recv(%WindowUpdate{window_size_increment: inc}, _state, stream) do
    stream = %{stream | window: stream.window + inc}

    flow =
      stream.flow
      |> Stream.FlowControl.increment_window(inc)
      |> Stream.FlowControl.process(stream.socket)

    {:keep_state, %{stream | flow: flow}}
  end

  def recv(%PushPromise{header_block_fragment: fragment}, state, stream)
    when state in [@idle] do

    {:ok, headers} = Hpack.decode(stream.decoder, fragment)
    stream = %Stream{stream | headers: stream.headers ++ headers}

    send(stream.connection, {:push_promise, Stream.Response.new(stream)})
    {:next_state, @reserved_remote, stream}
  end

  def recv(%RstStream{}, state, stream)
    when state in [@open, @half_closed_local, @half_closed_remote, @closed] do
    # IO.inspect(frame, label: "Got RST_STREAM")
    {:next_state, :closed, stream}
  end

  def recv(%Continuation{header_block_fragment: fragment}, _state, stream) do
    {:ok, headers} = Hpack.decode(stream.decoder, fragment)
    stream = %Stream{stream | headers: stream.headers ++ headers}

    {:keep_state, stream}
  end

  def recv(frame, state, stream) do
    Logger.info("""
    Unknown RECV on stream #{stream.id}
    Frame: #{inspect(frame)}
    State: #{inspect(state)}
    """)
    {:keep_state, stream}
  end

  # Enter Events

  def handle_event(:enter, _old, @half_closed_remote, stream) do
    bin = stream.id |> RstStream.new |> Encodable.to_bin
    :ssl.send(stream.socket, bin)

    :gen_statem.cast(self(), :close)
    {:keep_state, stream}
  end
  def handle_event(:enter, _old, @closed, stream) do
    send(stream.connection, {:finished, Stream.Response.new(stream)})
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
    IO.inspect("""
    === Unknown cast ===
    #{inspect(msg)}
    State: #{inspect(state)}
    Stream: #{inspect(stream)}
    """)
    {:keep_state, stream}
  end

  # Calls

  def handle_event({:call, from},
                   {:recv, %WindowUpdate{window_size_increment: inc}},
                   _state,
                   stream) do

    stream = %{stream | window: stream.window + inc}
    {:keep_state, stream, {:reply, from, :ok}}
  end

  def handle_event({:call, from},
                   {:send_headers, headers, payload},
                   _state,
                   stream) do

    headers = add_headers(headers, stream)

    {:ok, encoded} = Hpack.encode(stream.encoder, headers)
    headers_payload = :erlang.iolist_to_binary(encoded)

    h = Http2.build_frame(@headers, 0x4, stream.id, headers_payload)
    :ssl.send(stream.socket, h)
    # IO.puts("Sending, Stream ID: #{stream.id}")

    flow =
      if payload do
        stream.flow
        |> Stream.FlowControl.add(payload)
        |> Stream.FlowControl.process(stream.socket)
      else
        stream.flow
      end

    stream = %{stream | flow: flow}

    {:next_state, @open, stream, [{:reply, from, :ok}]}
  end

  def send_chunks(_socket, _stream_id, []), do: :ok
  def send_chunks(socket, stream_id, [chunk | []]) do
    h_p = Http2.build_frame(@data, 0x1, stream_id, chunk)
    :ssl.send(socket, h_p)
  end
  def send_chunks(socket, stream_id, [chunk | rest]) do
    h_p = Http2.build_frame(@data, 0x0, stream_id, chunk)
    :ssl.send(socket, h_p)

    send_chunks(socket, stream_id, rest)
  end

  def chunk(size, bin) when byte_size(bin) >= size do
    {chunk, rest} = :erlang.split_binary(bin, size)
    [chunk | chunk(size, rest)]
  end
  def chunk(_size, <<>>), do: []
  def chunk(_size, bin), do: [bin]

  def add_headers(headers, stream) do
    h = headers ++
    [
      {":scheme", Atom.to_string(stream.scheme)},
      {":authority", List.to_string(stream.uri)}
    ]
    # sorting headers to have pseudo headers first.
    Enum.sort(h, fn({a, _b}, {c, _d}) -> a < c end)
  end

  # Other Callbacks

  def init(stream), do: {:ok, @idle, stream}

  def callback_mode, do: [:handle_event_function, :state_enter]

  def terminate(_reason, _state, _data), do: :void

  def code_change(_vsn, state, data, _extra), do: {:ok, state, data}
end
