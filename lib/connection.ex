defmodule Kadabra.Connection do
  @moduledoc """
    Worker for maintaining an open HTTP/2 connection.
  """
  use GenServer
  require Logger

  alias Kadabra.{Error, Frame, Http2, Stream}
  alias Kadabra.Frame.{Continuation, Data, Goaway, Headers, Ping,
    PushPromise, RstStream, WindowUpdate}

  @data 0x0
  @headers 0x1
  @rst_stream 0x3
  @settings 0x4
  @push_promise 0x5
  @ping 0x6
  @goaway 0x7
  @window_update 0x8
  @continuation 0x9

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

  defp initial_state(socket, uri, pid, opts) do
   encoder = :hpack.new_context
   decoder = :hpack.new_context
   %{
      buffer: "",
      client: pid,
      uri: uri,
      scheme: opts[:scheme] || :https,
      opts: opts,
      socket: socket,
      stream_id: 1,
      streams: %{},
      reconnect: opts[:reconnect] || :true,
      encoder_state: encoder,
      decoder_state: decoder
    }
  end

  def do_connect(uri, opts) do
    case opts[:scheme] do
      :http -> {:error, :not_implemented}
      :https -> do_connect_ssl(uri, opts)
      _ -> {:error, :bad_scheme}
    end
  end

  def do_connect_ssl(uri, opts) do
    :ssl.start()
    ssl_opts = ssl_options(opts[:ssl])
    case :ssl.connect(uri, opts[:port], ssl_opts) do
      {:ok, ssl} ->
        :ssl.send(ssl, Http2.connection_preface)
        :ssl.send(ssl, Http2.settings_frame)
        {:ok, ssl}
      {:error, reason} ->
        {:error, reason}
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

  def handle_cast({:recv, %Goaway{} = frame}, state) do
    do_recv_goaway(frame, state)
    {:noreply, state}
  end

  def handle_cast({:recv, %Frame.Settings{} = frame}, state) do
    state = do_recv_settings(frame, state)
    {:noreply, state}
  end

  def handle_cast({:send, :ping}, %{socket: socket} = state) do
    bin = Ping.new |> Ping.to_bin
    :ssl.send(socket, bin)
    {:noreply, state}
  end

  def handle_cast({:recv, %Ping{ack: ack}}, %{client: pid} = state) do
    resp = if ack, do: :pong, else: :ping
    send(pid, {resp, self()})
    {:noreply, state}
  end

  def handle_cast({:recv, :rst_stream, frame}, state) do
    {:noreply, do_recv_rst_stream(frame, state)}
  end

  def handle_cast({:recv, %WindowUpdate{}}, state) do
    # TODO: Handle window updates
    {:noreply, state}
  end

  def handle_cast(msg, state) do
    IO.inspect msg
    {:noreply, state}
  end

  defp inc_stream_id(%{stream_id: stream_id} = state) do
    %{state | stream_id: stream_id + 2}
  end

  defp do_recv_data(%{stream_id: stream_id} = frame, %{client: pid} = state) do
    stream = get_stream(stream_id, state)
    body = stream.body || ""
    stream = %Stream{stream | body: body <> frame[:payload]}

    if frame[:flags] == 0x1, do: send pid, {:end_stream, stream}

    put_stream(stream_id, state, stream)
  end

  defp do_recv_headers(%{stream_id: stream_id, flags: flags, payload: payload},
                       %{client: pid, decoder_state: dec} = state) do

    stream = get_stream(stream_id, state)
    {:ok, {headers, new_dec}} = :hpack.decode(payload, dec)
    stream = %Stream{ stream | headers: headers }

    state = %{state | decoder_state: new_dec}

    if flags == 0x5, do: send pid, {:end_stream, stream}

    put_stream(stream_id, state, stream)
  end

  defp do_send_headers(headers, payload, %{socket: socket,
                                           stream_id: stream_id,
                                           uri: uri,
                                           socket: socket,
                                           encoder_state: encoder,
                                           decoder_state: decoder} = state) do

    {:ok, pid} =
      %Stream{
        id: stream_id,
        uri: uri,
        connection: self(),
        socket: socket,
        encoder: encoder,
        decoder: decoder
      }
      |> Stream.start_link

    Registry.register(Registry.Kadabra, {uri, stream_id}, pid)

    :gen_statem.cast(pid, {:send_headers, headers, payload})

    state
  end

  defp do_send_goaway(%{socket: socket, stream_id: stream_id}) do
    bin = stream_id |> Goaway.new |> Goaway.to_bin
    :ssl.send(socket, bin)
  end

  defp do_recv_goaway(%Goaway{last_stream_id: id,
                              error_code: error,
                              debug_data: debug}, %{client: pid} = state) do
    log_goaway(error, id, debug)
    send pid, {:closed, self()}
    {:noreply, %{state | streams: %{}}}
  end

  def log_goaway(code, id, bin) do
    error = Error.string(code)
    Logger.error "Got GOAWAY, #{error}, Last Stream: #{id}, Rest: #{bin}"
  end

  defp do_recv_settings(%Frame.Settings{settings: settings} = frame,
                        %{socket: socket,
                          client: pid,
                          decoder_state: decoder}  = state) do

    if frame.ack do
      send pid, {:ok, self()}
      state
    else
      settings_ack = Http2.build_frame(@settings, 0x1, 0x0, <<>>)
      #settings = parse_settings(frame[:payload])
      #table_size = fetch_setting(settings, "SETTINGS_MAX_HEADER_LIST_SIZE")

      new_decoder = :hpack.new_max_table_size(settings.max_header_list_size, decoder)

      :ssl.send(socket, settings_ack)
      send pid, {:ok, self()}
      %{state | decoder_state: new_decoder}
    end 
  end

  defp do_recv_rst_stream(frame, %{client: pid} = state) do
    code = :binary.decode_unsigned(frame[:payload])
    _error = Error.string(code)
    send pid, {:end_stream, get_stream(frame[:stream_id], state)}
  end

  defp put_stream(id, state, stream) do
    id = Integer.to_string(id)
    put_in(state, [:streams, id], stream)
  end

  defp get_stream(id, state) do
    id_string = Integer.to_string(id)
    state[:streams][id_string] || %Kadabra.Stream{id: id}
  end

  def handle_info({:finished, response}, %{client: pid} = state) do
    send(pid, {:end_stream, response})
    {:noreply, state}
  end

  def handle_info({:push_promise, stream}, %{client: pid} = state) do
    send(pid, {:push_promise, stream})
    {:noreply, state}
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
      {:error, bin} ->
        :ssl.setopts(socket, [{:active, :once}])
        {:noreply, %{state | buffer: bin}}
    end
  end

  def parse_ssl(socket, bin, state) do
    case Http2.parse_frame(bin) do
      {:ok, frame, rest} ->
        handle_response(frame, state)
        parse_ssl(socket, rest, state)
      {:error, bin} ->
        {:error, bin}
    end
  end

  def handle_response(frame, _state) when is_binary(frame) do
    Logger.info "Got binary: #{inspect(frame)}"
  end
  def handle_response(frame, state) do
    pid =
      case Registry.lookup(Registry.Kadabra, {state.uri, frame.stream_id}) do
        [{_self, pid}] -> pid
        [] -> self()
      end

    case frame[:frame_type] do
      @data ->
        :gen_statem.cast(pid, {:recv, Data.new(frame)})
      @headers ->
        :gen_statem.cast(pid, {:recv, Headers.new(frame)})
      @rst_stream ->
        :gen_statem.cast(pid, {:recv, RstStream.new(frame)})
      @settings ->
        handle_settings(frame)
      @push_promise ->
        open_promise_stream(frame, state)
      @ping ->
        GenServer.cast(self(), {:recv, Ping.new(frame)})
      @goaway ->
        GenServer.cast(self(), {:recv, Goaway.new(frame)})
      @window_update ->
        GenServer.cast(self(), {:recv, WindowUpdate.new(frame)})
      @continuation ->
        :gen_statem.cast(pid, {:recv, Continuation.new(frame)})
      _ ->
        Logger.debug("Unknown frame: #{inspect(frame)}")
    end
  end

  def handle_settings(frame) do
    case Frame.Settings.new(frame) do
      {:ok, s} ->
        GenServer.cast(self(), {:recv, s})
      _else ->
        # TODO: handle bad settings
        :error
    end
  end

  def open_promise_stream(frame, state) do
    pp_frame = PushPromise.new(frame)
    {:ok, pid} =
      %Stream{
        id: pp_frame.stream_id,
        uri: state.uri,
        connection: self(),
        socket: state.socket,
        encoder: state.encoder_state,
        decoder: state.decoder_state
      }
      |> Stream.start_link

    Registry.register(Registry.Kadabra, {state.uri, pp_frame.stream_id}, pid)
    GenServer.cast(pid, {:recv, pp_frame})
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
        {:noreply, reset_state(state, socket)}
      {:error, error} ->
        Logger.error "Socket closed, reopening failed with #{error}"
        state |> inspect |> Logger.info
        send(pid, :closed)
         {:stop, :normal, state}
    end
  end

  defp reset_state(state, socket) do
    encoder = :hpack.new_context
    decoder = :hpack.new_context
    %{state | encoder_state: encoder,
              decoder_state: decoder,
              socket: socket,
              streams: %{}}
  end
end
