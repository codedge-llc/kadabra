defmodule Kadabra.Stream do
  @moduledoc false

  defstruct id: nil,
            flow: nil,
            headers: [],
            body: "",
            state: @idle,
            on_response: nil

  require Logger

  alias Kadabra.{Hpack, Http2, Stream}
  alias Kadabra.Connection.{Settings, Socket}

  alias Kadabra.Frame.{
    Continuation,
    Data,
    Headers,
    PushPromise,
    RstStream,
    WindowUpdate
  }

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
    # IO.inspect(frame, label: "Got RST_STREAM")
    if stream.state in [@open, @hc_local, @hc_remote, @closed] do
      %Stream{stream | state: @closed}
    else
      stream
    end
  end

  # For SETTINGS initial_window_size and max_frame_size changes
  def recv({:settings_change, window, new_max_frame}, _state, stream) do
    flow =
      stream.flow
      |> Stream.FlowControl.increment_window(window)
      |> Stream.FlowControl.set_max_frame_size(new_max_frame)

    {:keep_state, %{stream | flow: flow}}
  end

  def recv(stream, %WindowUpdate{window_size_increment: inc}, conn) do
    flow =
      stream.flow
      |> Stream.FlowControl.increment_window(inc)
      |> Stream.FlowControl.process(conn.socket)

    %Stream{stream | flow: flow}
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
end
