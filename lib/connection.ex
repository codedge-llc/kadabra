defmodule Kadabra.Connection do
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
    Logger.debug "Initializing..."
    case do_connect(uri, opts) do
      {:ok, socket} ->
        {:ok, initial_state(socket, uri, pid)}
      {:error, error} ->
        Logger.error(inspect(error))
        {:error, error}
    end
  end

  defp initial_state(socket, uri, pid) do
   %{
      buffer: "",
      client: pid,
      uri: uri,
      socket: socket,
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

  def handle_cast({:recv, :data, %{stream_id: stream_id} = frame}, %{socket: socket} = state) do
    Logger.debug """
      Got DATA, Stream: #{frame[:stream_id]}, Flags: #{frame[:flags]}
      --
      #{frame[:payload]}
    """
    stream = get_stream(stream_id, state)
    stream = %Stream{ stream | body: frame[:payload] }
    state = put_stream(stream_id, state, stream)
    {:noreply, state}
  end

  def handle_cast({:recv, :headers, %{stream_id: stream_id} = frame}, %{socket: socket, client: pid} = state) do
    stream = get_stream(stream_id, state)
    headers = Http2.decode_headers(frame[:payload])
    stream = %Stream{ stream | headers: headers }
    state = put_stream(stream_id, state, stream)
    {:noreply, state}
  end

  def handle_cast({:send, :headers, headers}, %{socket: socket, stream_id: stream_id, uri: uri} = state) do
    headers = headers ++ [{"host", List.to_string(uri)}]
    encoded = for {key, value} <- headers, do: Http2.encode_header(key, value)
    payload = Enum.reduce(encoded, <<>>, fn(x, acc) -> acc <> x end)
    h = Http2.build_frame(@headers, 0x4, stream_id, payload)
    
    :ssl.send(socket, h)

    {:noreply, %{state | stream_id: stream_id + 2}}
  end

  def handle_cast({:recv, :settings, frame}, %{socket: socket, client: pid} = state) do
    settings_ack = Http2.build_frame(0x4, 0x1, 0x0, <<>>)
    settings = parse_settings(frame[:payload])
    Logger.debug(inspect(settings))
    :ssl.send(socket, settings_ack)
    send pid, {:ok, self}
    {:noreply, state}
  end

  def handle_cast({:recv, :rst_stream, frame}, %{socket: socket, client: pid} = state) do
    code = :binary.decode_unsigned(frame[:payload])
    error = Error.to_string(code)
    Logger.error "Got RST_STREAM, #{error}"
    send pid, {:rst_stream, get_stream(frame[:stream_id], state)}
    {:noreply, state}
  end

  defp put_stream(id, state, stream) do
    id = Integer.to_string(id)
    put_in(state, [:streams, id], stream)
  end

  defp get_stream(id, state) do
    id_string = Integer.to_string(id)
    state[:streams][id_string] || %Kadabra.Stream{id: id}
  end

  def handle_cast({:send, :ping}, %{socket: socket} = state) do
    :ssl.send(socket, Http2.build_frame(0x6, 0x0, 0x0, <<0, 0, 0, 0, 0, 0, 0, 0>>))
    {:noreply, state}
  end

  def handle_cast({:recv, :ping, frame}, state) do
    Logger.debug "Got PING"
    {:noreply, state}
  end

  def handle_info({:tcp, _socket, bin}, state) do
    Logger.debug("Recv TCP: #{inspect(bin) <> <<0>>}")
    {:noreply, state}
  end

  def handle_info({:ssl, socket, bin}, state) do
    buffer = state[:buffer] || ""
    to_parse = <<buffer::bitstring, bin::bitstring>>
    Logger.info("Recv SSL: #{inspect(bin)}")
    parse_ssl(socket, bin, state)
    {:noreply, state}
  end

  def parse_ssl(socket, bin, state) do
    case Http2.parse_frame(bin) do
      {:ok, frame, rest} ->
        handle_response(socket, frame)
        parse_ssl(socket, rest, state)
        {:noreply, state}
      {:error, bin} ->
        #new_buffer = <<state[:buffer], bin>>
        {:noreply, %{state | buffer: bin}}
    end
  end

  def handle_response(socket, frame) when is_binary(frame) do
    Logger.info inspect(frame)
  end
  def handle_response(socket, frame) do
    case frame[:frame_type] do
      @data -> 
        GenServer.cast(self, {:recv, :data, frame})
      @headers -> 
        GenServer.cast(self, {:recv, :headers, frame})
      @rst_stream -> 
        GenServer.cast(self, {:recv, :rst_stream, frame})
      @settings ->
        Logger.debug "Got SETTINGS"
        GenServer.cast(self, {:recv, :settings, frame})
      @ping ->
        GenServer.cast(self, {:recv, :ping, frame})
      @goaway ->
        <<r::1, last_stream_id::31, code::32>> = frame[:payload]
        Logger.error "Got GOAWAY, #{Error.to_string(code)}, Last Stream: #{last_stream_id}"
      @window_update ->
        Logger.debug "Got WINDOW_UPDATE" 
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

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.debug("Recv TCP close...")
    {:noreply, state}
  end

  def handle_info({:ssl_closed, _socket}, state) do
    Logger.debug("Recv SSL close...")
    {:noreply, state}
  end
end
