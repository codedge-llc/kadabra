defmodule Kadabra.Stream do
  @moduledoc """
  Struct returned from open connections.
  """
  defstruct [:id, :headers, :uri, :connection, :decoder, :encoder,
             :socket, body: "", scheme: :https]

  alias Kadabra.{Connection, Http2, Stream}
  alias Kadabra.Frame.{Continuation, Data, Headers, PushPromise, RstStream}

  @data 0x0
  @headers 0x1
  # @rst_stream 0x3
  # @settings 0x4
  # @ping 0x6
  # @goaway 0x7
  # @window_update 0x8

  @closed :closed
  @half_closed_local :half_closed_local
  @half_closed_remote :half_closed_remote
  @idle :idle
  @open :open
  # @reserved_local :reserved_local
  @reserved_remote :reserved_remote

  def new(%Connection{} = conn, stream_id) do
    %__MODULE__{
      id: stream_id,
      uri: conn.uri,
      connection: self(),
      socket: conn.socket,
      encoder: conn.encoder_state,
      decoder: conn.decoder_state,
    }
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

  def handle_event(:enter, _old, @half_closed_remote, stream) do
    bin = stream.id |> RstStream.new |> RstStream.to_bin
    :ssl.send(stream.socket, bin)

    :gen_statem.cast(self(), :close)
    {:keep_state, stream}
  end
  def handle_event(:enter, _old, @closed, stream) do
    send(stream.connection, {:finished, Stream.Response.new(stream)})
    {:keep_state, stream}
  end
  def handle_event(:enter, _old, _new, stream), do: {:keep_state, stream}

  def handle_event(:cast, :close, _state, stream) do
    {:next_state, @closed, stream}
  end

  def handle_event(:cast, {:recv, %RstStream{}}, state, stream)
    when state in [@open, @half_closed_local, @half_closed_remote, @closed] do
    {:next_state, :closed, stream}
  end

  def handle_event(:cast, {:recv, %Continuation{} = frame}, state, stream)
    when state in [@idle] do

    {:ok, {headers, new_dec}} = :hpack.decode(frame.header_block_fragment, stream.decoder)
    stream = %Stream{stream | headers: headers, decoder: new_dec}

    {:keep_state, stream}
  end

  def handle_event(:cast, {:recv, %PushPromise{} = frame}, state, stream)
    when state in [@idle] do

    {:ok, {headers, new_dec}} = :hpack.decode(frame.header_block_fragment, stream.decoder)
    stream = %Stream{stream | headers: headers, decoder: new_dec}

    send(stream.connection, {:push_promise, Stream.Response.new(stream)})
    {:next_state, @reserved_remote, stream}
  end

  def handle_event(:cast, {:recv, %Headers{} = frame}, _state, stream) do
    {:ok, {headers, new_dec}} = :hpack.decode(frame.header_block_fragment, stream.decoder)
    stream = %Stream{stream | headers: headers, decoder: new_dec}

    if frame.end_stream do
      {:next_state, @half_closed_remote, stream}
    else
      {:keep_state, stream}
    end
  end

  def handle_event(:cast, {:recv, %Data{end_stream: end_stream?,
                                        data: data}}, _state, stream) do
    stream = %Stream{stream | body: stream.body <> data}
    cond do
      end_stream? -> {:next_state, @half_closed_remote, stream}
      true -> {:keep_state, stream}
    end
  end

  def handle_event(:cast, {:send_headers, headers, payload}, _state, stream) do
    headers = add_headers(headers, stream)
    {:ok, {encoded, new_encoder}} = :hpack.encode(headers, stream.encoder)
    headers_payload = :erlang.iolist_to_binary(encoded)
    h = Http2.build_frame(@headers, 0x4, stream.id, headers_payload)

    stream = %{stream | encoder: new_encoder}

    :ssl.send(stream.socket, h)

    if payload do
      h_p = Http2.build_frame(@data, 0x1, stream.id, payload)
      :ssl.send(stream.socket, h_p)
    end

    {:next_state, @open, stream}
  end

  defp add_headers(headers, stream) do
    h = headers ++
    [
      {":scheme", Atom.to_string(stream.scheme)},
      {":authority", List.to_string(stream.uri)}
    ]
    # sorting headers to have pseudo headers first.
    Enum.sort(h, fn({a, _b}, {c, _d}) -> a < c end)
  end

  def init(stream) do
    {:ok, @idle, stream}
  end

  def callback_mode, do: [:handle_event_function, :state_enter]

  def terminate(_reason, _state, _data), do: :void

  def code_change(_vsn, state, data, _extra), do: {:ok, state, data}
end
