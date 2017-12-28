defmodule Kadabra.Connection.Socket do
  @moduledoc false

  defstruct socket: nil,
            scheme: :https,
            buffer: "",
            uri: nil,
            sup: nil,
            opts: []

  alias Kadabra.{Connection, FrameParser}

  require Logger

  @type ssl_sock :: {:sslsocket, any, pid | {any, any}}

  @type connection_result ::
          {:ok, ssl_sock}
          | {:ok, pid}
          | {:error, :not_implmenented}
          | {:error, :bad_scheme}

  def default_port(:http), do: 80
  def default_port(:https), do: 443
  def default_port(_), do: 443

  def start_link(uri, sup, opts) do
    name = via_tuple(sup)
    GenServer.start_link(__MODULE__, {uri, sup, opts}, name: name)
  end

  def init({uri, sup, opts}) do
    case connect(uri, opts) do
      {:ok, socket} ->
        state = %__MODULE__{
          uri: uri,
          sup: sup,
          scheme: Keyword.get(opts, :scheme, :https),
          opts: opts,
          socket: socket
        }

        {:ok, state}

      {:error, error} ->
        {:error, error}
    end
  end

  def via_tuple(ref) do
    {:via, Registry, {Registry.Kadabra, {ref, __MODULE__}}}
  end

  @spec connect(charlist, Keyword.t()) :: connection_result
  def connect(uri, opts) when is_binary(uri) do
    uri |> String.to_charlist() |> connect(opts)
  end

  def connect(uri, opts) do
    case opts[:scheme] do
      :http -> do_connect(uri, :http, opts)
      :https -> do_connect(uri, :https, opts)
      _ -> {:error, :bad_scheme}
    end
  end

  defp do_connect(uri, :http, opts) do
    tcp_opts =
      opts
      |> Keyword.get(:tcp, [])
      |> options(:http)

    :gen_tcp.connect(uri, opts[:port], tcp_opts)
  end

  defp do_connect(uri, :https, opts) do
    :ssl.start()

    ssl_opts =
      opts
      |> Keyword.get(:ssl, [])
      |> options(:https)

    :ssl.connect(uri, opts[:port], ssl_opts)
  end

  @spec options(Keyword.t(), :http | :https) :: [...]
  def options(opts, :https) do
    opts ++
      [
        {:active, :once},
        {:packet, :raw},
        {:reuseaddr, false},
        {:alpn_advertised_protocols, [<<"h2">>]},
        :binary
      ]
  end

  def options(opts, :http) do
    opts ++
      [
        {:active, :once},
        {:packet, :raw},
        {:reuseaddr, false},
        :binary
      ]
  end

  def sendf(pid, bin) do
    GenServer.call(pid, {:send, bin})
  end

  def setopts(pid, opts) do
    GenServer.cast(pid, {:setopts, opts})
  end

  def handle_call({:send, bin}, from, state) do
    GenServer.reply(from, :ok)
    do_send(state.socket, bin)
    {:noreply, state}
  end

  def handle_cast({:send, bin}, state) do
    do_send(state.socket, bin)
    {:noreply, state}
  end

  def handle_cast({:setopts, opts}, state) do
    do_setopts(state.socket, opts)
    {:noreply, state}
  end

  def do_send({:sslsocket, _, _} = pid, bin) do
    :ssl.send(pid, bin)
  end

  def do_send(pid, bin) do
    :gen_tcp.send(pid, bin)
  end

  def do_setopts({:sslsocket, _, _} = pid, opts) do
    :ssl.setopts(pid, opts)
  end

  def do_setopts(pid, opts) do
    :inet.setopts(pid, opts)
  end

  # handle_info

  def handle_info({:tcp, _socket, bin}, state) do
    do_recv_bin(bin, state)
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    handle_disconnect(state)
  end

  def handle_info({:ssl, _socket, bin}, state) do
    do_recv_bin(bin, state)
  end

  def handle_info({:ssl_closed, _socket}, state) do
    handle_disconnect(state)
  end

  defp do_recv_bin(bin, %{socket: socket} = state) do
    bin = state.buffer <> bin

    case parse_bin(socket, bin, state) do
      {:error, bin, state} ->
        do_setopts(socket, [{:active, :once}])
        {:noreply, %{state | buffer: bin}}
    end
  end

  def parse_bin(socket, bin, state) do
    case FrameParser.parse(bin) do
      {:ok, frame, rest} ->
        state.sup
        |> Connection.via_tuple()
        |> GenStage.cast({:recv, frame})

        parse_bin(socket, rest, state)

      {:error, bin} ->
        {:error, bin, state}
    end
  end

  def handle_disconnect(%{sup: pid} = state) do
    send(pid, {:closed, self()})
    {:noreply, %{state | socket: nil}}
  end
end
