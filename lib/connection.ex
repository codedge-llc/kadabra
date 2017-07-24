defmodule Kadabra.Connection do
  @moduledoc """
  Worker for maintaining an open HTTP/2 connection.
  """

  defstruct buffer: "",
            client: nil,
            uri: nil,
            scheme: :https,
            opts: [],
            socket: nil,
            stream_id: 1,
            reconnect: true,
            encoder_state: nil,
            decoder_state: nil

  use GenServer
  require Logger

  alias Kadabra.{Encodable, Error, Frame, Http2, Stream}
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
   %__MODULE__{
      client: pid,
      uri: uri,
      scheme: opts[:scheme] || :https,
      opts: opts,
      socket: socket,
      reconnect: opts[:reconnect] || true,
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

  def handle_cast({:recv, %Frame.Goaway{} = frame}, state) do
    do_recv_goaway(frame, state)
    {:noreply, state}
  end

  def handle_cast({:recv, %Frame.Settings{} = frame}, state) do
    state = do_recv_settings(frame, state)
    {:noreply, state}
  end

  def handle_cast({:recv, %Frame.Ping{ack: ack}}, %{client: pid} = state) do
    resp = if ack, do: :pong, else: :ping
    send(pid, {resp, self()})
    {:noreply, state}
  end

  def handle_cast({:recv, %Frame.WindowUpdate{}}, state) do
    # TODO: Handle window updates
    {:noreply, state}
  end

  def handle_cast({:send, :ping}, %{socket: socket} = state) do
    bin = Ping.new |> Encodable.to_bin
    :ssl.send(socket, bin)
    {:noreply, state}
  end

  def handle_cast(msg, state) do
    IO.inspect msg
    {:noreply, state}
  end

  defp inc_stream_id(%{stream_id: stream_id} = state) do
    %{state | stream_id: stream_id + 2}
  end

  defp do_send_headers(headers, payload, %{stream_id: id, uri: uri} = state) do

    {:ok, pid} =
      state
      |> Stream.new(id)
      |> Stream.start_link

    Registry.register(Registry.Kadabra, {uri, id}, pid)

    :gen_statem.cast(pid, {:send_headers, headers, payload})

    state
  end

  defp do_send_goaway(%{socket: socket, stream_id: stream_id}) do
    bin = stream_id |> Goaway.new |> Encodable.to_bin
    :ssl.send(socket, bin)
  end

  defp do_recv_goaway(%Goaway{last_stream_id: id,
                              error_code: error,
                              debug_data: debug}, %{client: pid} = state) do
    log_goaway(error, id, debug)
    send pid, {:closed, self()}
    {:noreply, state}
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
      send(pid, {:ok, self()})
      state
    else
      new_decoder = :hpack.new_max_table_size(settings.max_header_list_size, decoder)

      settings_ack = Http2.build_frame(@settings, 0x1, 0x0, <<>>)
      :ssl.send(socket, settings_ack)

      send(pid, {:ok, self()})

      %{state | decoder_state: new_decoder}
    end
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
    bin = state.buffer <> bin
    case parse_ssl(socket, bin, state) do
      {:error, bin} ->
        :ssl.setopts(socket, [{:active, :once}])
        {:noreply, %{state | buffer: bin}}
    end
  end

  def parse_ssl(socket, bin, state) do
    case Kadabra.Frame.new(bin) do
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
    pid = pid_for_stream(state.uri, frame.stream_id) || self()

    case frame.type do
      @data ->
        Stream.cast_recv(pid, Data.new(frame))
      @headers ->
        Stream.cast_recv(pid, Headers.new(frame))
      @rst_stream ->
        Stream.cast_recv(pid, RstStream.new(frame))
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
        Stream.cast_recv(pid, Continuation.new(frame))
      _ ->
        Logger.debug("Unknown frame: #{inspect(frame)}")
    end
  end

  def pid_for_stream(uri, stream_id) do
    case Registry.lookup(Registry.Kadabra, {uri, stream_id}) do
      [{_self, pid}] -> pid
      [] -> nil
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
      state
      |> Stream.new(pp_frame.stream_id)
      |> Stream.start_link

    Registry.register(Registry.Kadabra, {state.uri, pp_frame.stream_id}, pid)
    Stream.cast_recv(pid, pp_frame)
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
        {:noreply, reset_state(state, socket)}
      {:error, error} ->
        Logger.error "Socket closed, reopening failed with #{error}"
        send(pid, :closed)
         {:stop, :normal, state}
    end
  end

  defp reset_state(state, socket) do
    enc = :hpack.new_context
    dec = :hpack.new_context
    %{state | encoder_state: enc, decoder_state: dec, socket: socket}
  end
end
