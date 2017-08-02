defmodule Kadabra.Connection do
  @moduledoc """
    Worker for maintaining an open HTTP/2 connection.
  """
  use GenServer
  require Logger

  alias Kadabra.{Error, Http2, Stream}

  @data 0x0
  @headers 0x1
  @rst_stream 0x3
  @settings 0x4
  @ping 0x6
  @goaway 0x7
  @window_update 0x8

  def start_link(uri, pid, opts \\ []) do
    GenServer.start_link(__MODULE__, {:ok, uri, pid, opts})
  end

  def init({:ok, uri, pid, opts}) do
    case do_connect(uri, opts) do
      {:ok, socket} ->
        state = initial_state(socket, uri, pid, opts)
        {:ok, state}
      {:error, error} ->
        Logger.error(inspect(error))
        {:error, error}
    end
  end

  defp initial_state(socket, uri, pid, opts, stream_id \\ 1, streams \\ %{}) do
   encoder = :hpack.new_context
   decoder = :hpack.new_context
   %{
      buffer: "",
      client: pid,
      uri: uri,
      scheme: opts[:scheme] || :https,
      opts: opts,
      socket: socket,
      stream_id: stream_id,
      streams: streams,
      reconnect: opts[:reconnect],
      encoder_state: encoder,
      decoder_state: decoder
    }
  end

  def do_connect(uri, opts) do
    case opts[:scheme] do
      :http -> {:error, :not_implemented}
      :https ->
        :ssl.start
        case :ssl.connect(uri, opts[:port], ssl_options(opts[:ssl])) do
          {:ok, ssl} ->
            :ssl.send(ssl, Http2.connection_preface)
            :ssl.send(ssl, Http2.settings_frame)
            {:ok, ssl}
          {:error, reason} ->
            {:error, reason}
        end
      _ -> {:error, :bad_scheme}
    end
  end

  defp ssl_options(nil), do: ssl_options([])
  defp ssl_options(opts) do
    opts ++ [
      {:active, :once},
      {:packet, :raw},
      {:reuseaddr, false},
      {:alpn_advertised_protocols, [<<"h2">>]},
      :binary
    ]
  end

  def handle_call(:get_info, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_cast({:recv, :data, frame}, state) do
    state = do_recv_data(frame, state)
    {:noreply, state}
  end

  def handle_cast({:recv, :headers, frame}, state) do
    state = do_recv_headers(frame, state)
    {:noreply, state}
  end

  def handle_cast({:send, :headers, headers}, state) do
    new_state = do_send_headers(headers, nil, state)
    {:noreply, inc_stream_id(new_state)}
  end

  def handle_cast({:send, :headers, headers, payload}, state) do
    new_state = do_send_headers(headers, payload, state)
    {:noreply, inc_stream_id(new_state)}
  end

  def handle_cast({:send, :goaway}, state) do
    do_send_goaway(state)
    {:noreply, inc_stream_id(state)}
  end

  def handle_cast({:recv, :goaway, frame}, state) do
    do_recv_goaway(frame, state)
    {:noreply, state}
  end

  def handle_cast({:recv, :settings, frame}, state) do
    state = do_recv_settings(frame, state)
    {:noreply, state}
  end

  def handle_cast({:send, :ping}, %{socket: socket} = state) do
    ping = Http2.build_frame(0x6, 0x0, 0x0, <<0, 0, 0, 0, 0, 0, 0, 0>>)
    :ssl.send(socket, ping)
    {:noreply, state}
  end

  def handle_cast({:recv, :ping, _frame}, %{client: pid} = state) do
    send pid, {:ping, self()}
    {:noreply, state}
  end

  def handle_cast({:recv, :rst_stream, frame}, state) do
    {:noreply, do_recv_rst_stream(frame, state)}
  end

  def handle_cast({:recv, :window_update, %{stream_id: _stream_id,
                                            payload: payload}}, state) do

    <<_r::1, _window_size_inc::31>> = payload
    {:noreply, state}
  end

  defp inc_stream_id(%{stream_id: stream_id} = state) do
    %{state | stream_id: stream_id + 2}
  end

  defp do_recv_data(%{stream_id: stream_id} = frame, %{client: pid} = state) do
    stream = get_stream(stream_id, state)
    body = stream.body || ""
    stream = %Stream{stream | body: body <> frame[:payload]}

    if frame[:flags] == 0x1 do
     send pid, {:end_stream, stream}
     remove_stream(state, stream_id)
    else
      put_stream(stream_id, state, stream)
    end
  end

  defp do_recv_headers(%{stream_id: stream_id,
                         flags: flags,
                         payload: payload}, %{client: pid,
                                              decoder_state: dec} = state) do

    stream = get_stream(stream_id, state)
    {:ok, {headers, new_dec}} = :hpack.decode(payload, dec)
    status =
      headers
      |> get_status()
      |> String.to_integer
    stream = %Stream{stream | headers: headers, status: status}

    state = %{state | decoder_state: new_dec}

    if flags == 0x5 do
      send pid, {:end_stream, stream}
      remove_stream(state, stream_id)
    else
      put_stream(stream_id, state, stream)
    end
  end

  defp do_send_headers(headers, payload, %{socket: socket,
                                           stream_id: stream_id,
                                           uri: uri,
                                           encoder_state: encoder} = state) do

    headers = add_headers(headers, uri, state)
    {:ok, {encoded, new_encoder}} = :hpack.encode(headers, encoder)
    headers_payload = :erlang.iolist_to_binary(encoded)
    h = Http2.build_frame(@headers, 0x4, stream_id, headers_payload)

    :ssl.send(socket, h)

    if payload do
      chunks = chunk(10_000, payload)
      chunks |> inspect |> Logger.info
      send_chunks(socket, stream_id, chunks)
    end
    %{state | encoder_state: new_encoder}
  end

  defp send_chunks(socket, _stream_id, []), do: :ok
  defp send_chunks(socket, stream_id, [chunk | []]) do
    Logger.debug "Sending last chunk of size #{byte_size(chunk)}..."
    h_p = Http2.build_frame(@data, 0x1, stream_id, chunk)
    :ssl.send(socket, h_p)
  end
  defp send_chunks(socket, stream_id, [chunk | rest]) do
    Logger.debug "Sending chunk of size #{byte_size(chunk)}..."
    h_p = Http2.build_frame(@data, 0x0, stream_id, chunk)
    :ssl.send(socket, h_p)

    send_chunks(socket, stream_id, rest)
  end

  defp chunk(size, bin) when byte_size(bin) >= size do
    {chunk, rest} = :erlang.split_binary(bin, size)
    [chunk | chunk(size, rest)]
  end
  defp chunk(size, <<>>), do: []
  defp chunk(size, bin), do: [bin]

  defp add_headers(headers, uri, state) do
    h = headers ++
    [
      {":scheme", Atom.to_string(state[:scheme])},
      {":authority", List.to_string(uri)}
    ]
    # sorting headers to have pseudo headers first.
    Enum.sort(h, fn({a, _b}, {c, _d}) -> a < c end)
  end

  defp do_send_goaway(%{socket: socket, stream_id: stream_id}) do
    h = Http2.goaway_frame(stream_id, Error.code("NO_ERROR"))
    :ssl.send(socket, h)
  end

  defp do_recv_goaway(frame, %{client: pid} = state) do
    <<_r::1, last_stream_id::31, code::32, rest::binary>> = frame[:payload]
    log_goaway(code, last_stream_id, rest)

    send pid, {:closed, self()}
    {:noreply, %{state | streams: %{}}}
  end

  def log_goaway(code, id, bin) do
    error = Error.string(code)
    Logger.error "Got GOAWAY, #{error}, Last Stream: #{id}, Rest: #{bin}"
  end

  defp do_recv_settings(frame, %{socket: socket,
                                 client: pid,
                                 decoder_state: decoder}  = state) do
    case frame[:flags] do
      0x1 -> # SETTINGS ACK
        send pid, {:ok, self()}
        state
      _ ->
        settings_ack = Http2.build_frame(@settings, 0x1, 0x0, <<>>)
        settings = parse_settings(frame[:payload]) |> IO.inspect
        table_size = fetch_setting(settings, "SETTINGS_MAX_HEADER_LIST_SIZE")
        new_decoder = :hpack.new_max_table_size(table_size, decoder)

        :ssl.send(socket, settings_ack)
        send pid, {:ok, self()}
        %{state | decoder_state: new_decoder}
    end
  end

  def fetch_setting(settings, settings_key) do
    case Enum.find(settings, fn({key, _val}) -> key == settings_key end) do
      {^settings_key, value} -> value
      nil -> nil
    end
  end

  defp do_recv_rst_stream(frame, %{client: pid} = state) do
    code = :binary.decode_unsigned(frame[:payload])
    _error = Error.string(code)
    send pid, {:end_stream, get_stream(frame[:stream_id], state)}
    remove_stream(state, frame[:stream_id])
  end

  defp put_stream(id, state, stream) do
    id = Integer.to_string(id)
    put_in(state, [:streams, id], stream)
  end

  defp get_stream(id, state) do
    id_string = Integer.to_string(id)
    state[:streams][id_string] || %Kadabra.Stream{id: id}
  end

  defp remove_stream %{streams: streams} = state, id do
    id_string = Integer.to_string(id)
    %{state | streams: Map.delete(streams, id_string) }
  end

  def handle_info({:tcp, _socket, _bin}, state) do
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    maybe_reconnect(state)
  end

  def handle_info({:ssl, _socket, bin}, state) do
    do_recv_ssl(bin, state)
  end

  def handle_info({:ssl_closed, _socket}, state) do
   maybe_reconnect(state)
  end

  defp do_recv_ssl(bin, %{socket: socket} = state) do
    bin = state[:buffer] <> bin
    case parse_ssl(socket, bin, state) do
      :ok ->
        :ssl.setopts(socket, [{:active, :once}])
        {:noreply, %{state | buffer: ""}}
      {:error, bin} ->
        :ssl.setopts(socket, [{:active, :once}])
        {:noreply, %{state | buffer: bin}}
    end
  end

  def parse_ssl(socket, bin, state) do
    case Http2.parse_frame(bin) do
      {:ok, frame, rest} ->
        handle_response(frame)
        parse_ssl(socket, rest, state)
      {:error, bin} ->
        {:error, bin}
    end
  end

  def handle_response(frame) when is_binary(frame) do
    Logger.info "Got binary: #{inspect(frame)}"
  end

  def handle_response(frame) do
    case frame[:frame_type] do
      @data ->
        GenServer.cast(self(), {:recv, :data, frame})
      @headers ->
        GenServer.cast(self(), {:recv, :headers, frame})
      @rst_stream ->
        GenServer.cast(self(), {:recv, :rst_stream, frame})
      @settings ->
        GenServer.cast(self(), {:recv, :settings, frame})
      @ping ->
        GenServer.cast(self(), {:recv, :ping, frame})
      @goaway ->
        GenServer.cast(self(), {:recv, :goaway, frame})
      @window_update ->
        GenServer.cast(self(), {:recv, :window_update, frame})
      _ ->
        Logger.debug("Unknown frame: #{inspect(frame)}")
    end
  end

  def settings_param(identifier) do
    case identifier do
      0x1 -> "SETTINGS_HEADER_TABLE_SIZE"
      0x2 -> "SETTINGS_ENABLE_PUSH"
      0x3 -> "SETTINGS_MAX_CONCURRENT_STREAMS"
      0x4 -> "SETTINGS_INITIAL_WINDOW_SIZE"
      0x5 -> "SETTINGS_MAX_FRAME_SIZE"
      0x6 -> "SETTINGS_MAX_HEADER_LIST_SIZE"
      error -> "Unknown #{error}"
    end
  end

  def parse_settings(<<>>), do: []
  def parse_settings(bin) do
    <<identifier::16, value::32, rest::bitstring>> = bin
    [{settings_param(identifier), value}] ++ parse_settings(rest)
  end

  def maybe_reconnect(%{reconnect: false, client: pid} = state) do
    Logger.debug "Socket closed, not reopening, informing client"
    send(pid, {:closed, self()})
    {:stop, :normal, state}
  end

  def maybe_reconnect(%{reconnect: true, uri: uri, opts: opts, client: pid} = state) do
    case do_connect(uri, opts) do
      {:ok, socket} ->
        Logger.debug "Socket closed, reopened automatically"
        state |> inspect |> Logger.info
        encoder = :hpack.new_context
        decoder = :hpack.new_context
        {:noreply, %{state | encoder_state: encoder, decoder_state: decoder, socket: socket, streams: %{}}}
      {:error, error} ->
        Logger.error "Socket closed, reopening failed with #{error}"
        state |> inspect |> Logger.info
        send(pid, :closed)
         {:stop, :normal, state}
    end
  end

  defp get_status(headers) do
    case Enum.find(headers, fn({key, _val}) -> key == ":status" end) do
      {":status", status} -> status
      nil -> nil
    end
  end
end
