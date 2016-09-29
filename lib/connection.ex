defmodule Dos.Connection do
  use GenServer
  require Logger

  alias Dos.Http2

  @settings 0x4
  @ping 0x6
  @goaway 0x7
  @window_update 0x8

  def start_link(uri) do
    GenServer.start_link(__MODULE__, {:ok, uri})
  end

  def init({:ok, uri}) do
    Logger.debug "Initing..."
    case do_connect(uri) do
      {:ok, socket} ->
        {:ok, initial_state(socket)}
      {:error, error} ->
        Logger.error(inspect(error))
        {:error, error}
    end
  end

  defp initial_state(socket), do: %{socket: socket, stream_id: 1}

  def do_connect(uri) do
    options = [
               {:packet, 0},
               {:reuseaddr, false},
               {:active, true},
               {:alpn_advertised_protocols, [<<"h2">>]},
               :binary]
    :ssl.start
    case :ssl.connect(uri, 443, options) do
      {:ok, ssl} -> 
        Logger.debug "Establishing connection..."
        :ssl.send(ssl, Http2.connection_preface)
        {:ok, ssl}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def handle_cast({:recv, :settings, frame}, %{socket: socket} = state) do
    settings_ack = Http2.build_frame(0x4, 0x1, 0x0, <<>>)
    settings = parse_settings(frame[:payload])
    Logger.debug(inspect(settings))
    :ssl.send(socket, settings_ack)
    {:noreply, state}
  end

  def handle_cast({:send, :ping}, %{socket: socket} = state) do
    :ssl.send(socket, Http2.build_frame(0x6, 0x0, 0x0, <<0, 0, 0, 0, 0, 0, 0, 0>>))
    {:noreply, state}
  end

  def handle_cast({:recv, :ping, frame}, state) do
    Logger.debug "Got PING"
    {:noreply, state}
  end

  def establish_connection(uri, socket) do
  end

  def send_connection_preface(uri, socket) do
    req = 
      """
      HEAD / HTTP/1.1
      Host: #{uri}

      """
    #Logger.debug req
    #:gen_tcp.send(socket, req)
    :gen_tcp.send(socket, connection_preface)
  end

  def connection_preface, do: "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

  def parse_frame(<<payload_size::24, frame_type::8, flags::8, 0::1, stream_id::31, payload::binary>>) do
    %{
      payload_size: payload_size,
      frame_type: frame_type,
      flags: flags,
      stream_id: stream_id,
      payload: payload
    }
  end

  def handle_info({:tcp, _socket, bin}, state) do
    Logger.debug("Recv TCP: #{inspect(bin) <> <<0>>}")
    {:noreply, state}
  end

  def handle_info({:ssl, socket, bin}, state) do
    Logger.debug("Recv SSL: #{inspect(bin)}")
    frame = parse_frame(bin)
    handle_response(socket, frame)
    {:noreply, state}
  end

  def handle_response(socket, frame) do
    case frame[:frame_type] do
      @settings ->
        Logger.debug "Got SETTINGS"
        GenServer.cast(self, {:recv, :settings, frame})
      @ping ->
        GenServer.cast(self, {:recv, :ping, frame})
      @goaway ->
        <<r::1, last_stream_id::31, code::32>> = frame[:payload]
        Logger.error "Got GOAWAY, #{error_code(code)}, Last Stream: #{last_stream_id}"
      @window_update ->
        Logger.debug "Got WINDOW_UPDATE" 
      _ ->
        Logger.debug("Unknown frame: #{inspect(frame)}")
    end
  end

  def error_code(code) do
    case code do
      0x0 -> "NO_ERROR"
      0x1 -> "PROTOCOL_ERROR"
      0x2 -> "INTERNAL_ERROR"
      0x3 -> "FLOW_CONTROL_ERROR"
      0x4 -> "SETTINGS_TIMEOUT"
      0x5 -> "STREAM_CLOSED"
      0x6 -> "FRAME_SIZE_ERROR"
      0x7 -> "REFUSED_STREAM"
      0x8 -> "CANCEL"
      0x9 -> "COMPRESSION_ERROR"
      0xa -> "CONNECT_ERROR"
      0xb -> "ENHANCE_YOUR_CALM"
      0xc -> "INADEQUATE_SECURITY"
      0xd -> "HTTP_1_1_REQUIRED"
      error -> "Unknown Error: #{inspect(error)}"
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
