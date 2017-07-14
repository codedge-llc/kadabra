defmodule Kadabra.Stream do
  @moduledoc """
  Struct returned from open connections.
  """
  defstruct [:id, :headers, :body, :uri, :connection, :decoder, :encoder,
             :socket, scheme: :https]

  alias Kadabra.{Http2, Stream}

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
  @reserved :reserved

  def start_link(stream) do
    :gen_statem.start_link(__MODULE__, stream, [])
  end

  def handle_event(:enter, _old, @half_closed_remote, stream) do
    # TODO: send ES here
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

  def handle_event(:cast, {:recv_push_promise, %{payload: payload} = frame}, state, stream)
    when state in [@idle] do

    {:ok, {headers, new_dec}} = :hpack.decode(payload, stream.decoder)
    stream = %Stream{stream | headers: headers, decoder: new_dec}

    send(stream.connection, {:push_promise, Stream.Response.new(stream)})
    {:next_state, @reserved, stream}
  end

  def handle_event(:cast, {:recv_headers, %{flags: flags, payload: payload}}, _state, stream) do
    {:ok, {headers, new_dec}} = :hpack.decode(payload, stream.decoder)
    stream = %Stream{stream | headers: headers, decoder: new_dec}

    case flags do
      0x5 -> {:next_state, @half_closed_remote, stream}
      _ -> {:keep_state, stream}
    end
  end

  def handle_event(:cast, {:recv_data, %{flags: flags, payload: payload}}, _state, stream) do
    body = stream.body || ""
    stream = %Stream{stream | body: body <> payload}
    case flags do
      0x1 -> {:next_state, @half_closed_remote, stream}
      _ -> {:keep_state, stream}
    end
  end

  def handle_event(:cast, {:recv_rst_stream, _frame}, state, stream)
    when state in [@open, @half_closed_local, @half_closed_remote] do
    {:next_state, :closed, stream}
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
