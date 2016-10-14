defmodule Kadabra.Connection do
  use GenServer
  require Logger

  alias Kadabra.{Error, Hpack, Http2, Stream}

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
    Logger.debug "Initializing..."
    case do_connect(uri, opts) do
      {:ok, socket} ->
        {:ok, initial_state(socket, uri, pid, opts)}
      {:error, error} ->
        Logger.error(inspect(error))
        {:error, error}
    end
  end

  defp initial_state(socket, uri, pid, opts) do
   %{
      buffer: "",
      client: pid,
      uri: uri,
      scheme: opts[:scheme] || :https,
      socket: socket,
      dynamic_table: %Kadabra.Hpack{},
      stream_id: 1,
      streams: %{}
    }
  end

  def do_connect(uri, opts) do
    case opts[:scheme] do
      :http -> {:error, :not_implemented}
      :https -> 
        :ssl.start
        port = opts[:port] || 443
        case :ssl.connect(uri, port, ssl_options(opts[:ssl])) do
          {:ok, ssl} -> 
            Logger.debug "Establishing connection..."
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
      {:active, true},
      {:packet, :raw},
      {:reuseaddr, false},
      {:alpn_advertised_protocols, [<<"h2">>]},
      :binary
    ]
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
    do_send_headers(headers, nil, state)
    {:noreply, inc_stream_id(state)}
  end

  def handle_cast({:send, :headers, headers, payload}, state) do
    do_send_headers(headers, payload, state)
    {:noreply, inc_stream_id(state)}
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
    do_recv_settings(frame, state)
    {:noreply, state}
  end

  def handle_cast({:send, :ping}, %{socket: socket} = state) do
    :ssl.send(socket, Http2.build_frame(0x6, 0x0, 0x0, <<0, 0, 0, 0, 0, 0, 0, 0>>))
    {:noreply, state}
  end

  def handle_cast({:recv, :ping, _frame}, %{client: pid} = state) do
    Logger.debug "Got PING"
    send pid, {:ping, self}
    {:noreply, state}
  end

  def handle_cast({:recv, :rst_stream, frame}, state) do
    do_recv_rst_stream(frame, state)
    {:noreply, state}
  end

  def handle_cast({:recv, :window_update, frame}, state) do
    #window_size_inc = :binary.decode_unsigned(frame[:payload])
    <<_r::1, window_size_inc::31>> = frame[:payload]
    Logger.warn "Got WINDOW_UPDATE, Stream: #{frame[:stream_id]}, Inc: #{window_size_inc}"
    {:noreply, state}
  end

  defp inc_stream_id(%{stream_id: stream_id} = state), do: %{state | stream_id: stream_id + 2}

  defp do_recv_data(%{stream_id: stream_id} = frame, %{client: pid} = state) do
    Logger.debug """
      Got DATA, Stream: #{frame[:stream_id]}, Flags: #{frame[:flags]}
      --
      #{frame[:payload]}
    """
    case frame[:flags] do
      0x1 ->
        stream = get_stream(stream_id, state)
        stream = %Stream{ stream | body: frame[:payload] }
        send pid, {:rst_stream, stream}
        put_stream(stream_id, state, stream)
      _ -> 
        stream = get_stream(stream_id, state)
        stream = %Stream{ stream | body: frame[:payload] }
        put_stream(stream_id, state, stream)
    end
  end

  defp do_recv_headers(%{stream_id: stream_id} = frame, %{client: pid, dynamic_table: table} = state) do
    case frame[:flags] do
      0x5 ->
        stream = get_stream(stream_id, state)
        {headers, table} = Hpack.decode_headers(frame[:payload], table)
        Logger.debug """
          Got HEADERS, Stream: #{frame[:stream_id]}, Flags: #{frame[:flags]}
          --
          #{inspect(headers)}
          --
          #{inspect(table)}
        """
    
        stream = %Stream{ stream | headers: headers }
        state = %{state | dynamic_table: table }
        send pid, {:rst_stream, stream}
        put_stream(stream_id, state, stream)
      _ -> 
        stream = get_stream(stream_id, state)
        {headers, table} = Hpack.decode_headers(frame[:payload], table)
        Logger.debug """
          Got HEADERS, Stream: #{frame[:stream_id]}, Flags: #{frame[:flags]}
          --
          #{inspect(headers)}
          --
          #{inspect(table)}
        """

        stream = %Stream{ stream | headers: headers }
        state = %{state | dynamic_table: table }
        put_stream(stream_id, state, stream)
    end
  end

  defp do_send_headers(headers, payload,
    %{socket: socket, stream_id: stream_id, uri: uri} = state) do

    headers = add_headers(headers, uri, state)
    encoded = for {key, value} <- headers, do: Http2.encode_header(key, value)
    headers_payload = Enum.reduce(encoded, <<>>, fn(x, acc) -> acc <> x end)
    h = Http2.build_frame(@headers, 0x4, stream_id, headers_payload)

    :ssl.send(socket, h)
    
    if payload do
      h_p = Http2.build_frame(@data, 0x1, stream_id, payload)
      :ssl.send(socket, h_p)
    end
  end

  defp add_headers(headers, uri, state) do
    headers ++ [
      {":scheme", Atom.to_string(state[:scheme])},
      {"host", List.to_string(uri)}
    ]
  end

  defp do_send_goaway(%{socket: socket, stream_id: stream_id}) do
    Logger.debug "Sending goaway with last stream #{stream_id} with error #{Error.code("NO_ERROR")}"
    h = Http2.goaway_frame(stream_id, Error.code("NO_ERROR"))
    :ssl.send(socket, h)
  end

  defp do_recv_goaway(frame, %{client: pid} = state) do
    <<_r::1, last_stream_id::31, code::32, rest::binary>> = frame[:payload]
    Logger.error "Got GOAWAY, #{Error.string(code)}, Last Stream: #{last_stream_id}, Rest: #{rest}"

    send pid, {:closed, self}
    {:noreply, state}
  end

  defp do_recv_settings(frame, %{socket: socket, client: pid}) do
    case frame[:flags] do
      0x1 -> 
        Logger.debug "Got SETTINGS ACK"
        send pid, {:ok, self}
      _ ->
        Logger.debug "Got SETTINGS"
        settings_ack = Http2.build_frame(@settings, 0x1, 0x0, <<>>)
        settings = parse_settings(frame[:payload])
        Logger.debug(inspect(settings))
        :ssl.send(socket, settings_ack)
        send pid, {:ok, self}
    end
  end

  defp do_recv_rst_stream(frame, %{client: pid} = state) do
    code = :binary.decode_unsigned(frame[:payload])
    error = Error.string(code)
    Logger.error "Got RST_STREAM, #{error}"
    send pid, {:rst_stream, get_stream(frame[:stream_id], state)}
  end

  defp put_stream(id, state, stream) do
    id = Integer.to_string(id)
    put_in(state, [:streams, id], stream)
  end

  defp get_stream(id, state) do
    id_string = Integer.to_string(id)
    state[:streams][id_string] || %Kadabra.Stream{id: id}
  end

  def handle_info({:tcp, _socket, bin}, state) do
    Logger.debug("Recv TCP: #{inspect(bin) <> <<0>>}")
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.debug("Recv TCP close...")
    {:noreply, state}
  end

  def handle_info({:ssl, socket, bin}, state) do
    Logger.info("Recv SSL: #{inspect(bin)}")
    do_recv_ssl(bin, state)
  end

  def handle_info({:ssl_closed, _socket}, state) do
    Logger.debug("Recv SSL close...")
    {:noreply, state}
  end

  defp do_recv_ssl(bin, %{socket: socket} = state) do
    #Logger.warn("Buffer is #{inspect(state[:buffer])}")
    bin = state[:buffer] <> bin
    #Logger.warn("Now its is #{inspect(bin)}")
    case parse_ssl(socket, bin, state) do
      :ok -> 
        # Logger.debug "Got ok"
        {:noreply, %{state | buffer: ""}}
      {:error, bin} ->
        # Logger.debug "Got error, #{inspect(bin)}"
        {:noreply, %{state | buffer: bin}}
    end
  end

  def parse_ssl(socket, bin, state) do
    Logger.debug "Parsing: #{inspect(bin)}"
    case Http2.parse_frame(bin) do
      {:ok, frame, rest} ->
        Logger.debug inspect(frame)
        handle_response(frame)
        parse_ssl(socket, rest, state)
        :ok
      {:error, bin} ->
        Logger.error inspect(bin)
        {:error, bin}
    end
  end

  def handle_response(frame) when is_binary(frame) do
    Logger.info "Got binary: #{inspect(frame)}"
  end
  def handle_response(frame) do
    case frame[:frame_type] do
      @data -> 
        GenServer.cast(self, {:recv, :data, frame})
      @headers ->
        GenServer.cast(self, {:recv, :headers, frame})
      @rst_stream -> 
        GenServer.cast(self, {:recv, :rst_stream, frame})
      @settings ->
        GenServer.cast(self, {:recv, :settings, frame})
      @ping ->
        GenServer.cast(self, {:recv, :ping, frame})
      @goaway ->
        GenServer.cast(self, {:recv, :goaway, frame})
      @window_update ->
        GenServer.cast(self, {:recv, :window_update, frame})
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
end
