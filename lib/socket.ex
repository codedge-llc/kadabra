defmodule Kadabra.Socket do
  @moduledoc false

  defstruct socket: nil, buffer: "", active_user: nil

  alias Kadabra.FrameParser

  import Kernel, except: [send: 2]

  use GenServer

  @type ssl_sock :: {:sslsocket, any, pid | {any, any}}

  @type connection_result ::
          {:ok, ssl_sock}
          | {:ok, pid}
          | {:error, :not_implmenented}
          | {:error, :bad_scheme}

  @spec connection_preface() :: String.t()
  def connection_preface, do: "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

  def send(pid, bin) do
    GenServer.call(pid, {:send, bin})
  end

  def set_active(pid) do
    GenServer.call(pid, {:set_active, self()})
  end

  def start_link(uri, opts) do
    GenServer.start_link(__MODULE__, {uri, opts})
  end

  def init({uri, opts}) do
    case connect(uri, opts) do
      {:ok, socket} ->
        socket_send(socket, connection_preface())
        {:ok, %__MODULE__{socket: socket}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @spec connect(URI.t(), Keyword.t()) :: connection_result
  defp connect(uri, opts) do
    case uri.scheme do
      "http" -> do_connect(uri, :http, opts)
      "https" -> do_connect(uri, :https, opts)
      _ -> {:error, :bad_scheme}
    end
  end

  defp do_connect(uri, :http, opts) do
    tcp_opts =
      opts
      |> Keyword.get(:tcp, [])
      |> options(:http)

    uri.host
    |> to_charlist()
    |> :gen_tcp.connect(uri.port, tcp_opts)
  end

  defp do_connect(uri, :https, opts) do
    :ssl.start()

    ssl_opts =
      opts
      |> Keyword.get(:ssl, [])
      |> options(:https)

    uri.host
    |> to_charlist()
    |> :ssl.connect(uri.port, ssl_opts)
  end

  @spec options(Keyword.t(), :http | :https) :: [...]
  defp options(opts, :https) do
    opts ++
      [
        {:active, :once},
        {:packet, :raw},
        {:reuseaddr, false},
        {:verify, :verify_peer},
        {:depth, 99},
        {:cacerts, :certifi.cacerts()},
        {:alpn_advertised_protocols, [<<"h2">>]},
        :binary
      ]
  end

  defp options(opts, :http) do
    opts ++
      [
        {:active, :once},
        {:packet, :raw},
        {:reuseaddr, false},
        :binary
      ]
  end

  # Frame recv and parsing

  defp do_recv_bin(bin, %{socket: socket} = state) do
    bin = state.buffer <> bin

    case parse_bin(socket, bin, state) do
      {:unfinished, bin, state} ->
        setopts(state.socket, [{:active, :once}])
        {:noreply, %{state | buffer: bin}}
    end
  end

  def parse_bin(_socket, bin, %{active_user: nil} = state) do
    {:unfinished, bin, state}
  end

  def parse_bin(socket, bin, state) do
    case FrameParser.parse(bin) do
      {:ok, frame, rest} ->
        Kernel.send(state.active_user, {:recv, frame})
        parse_bin(socket, rest, state)

      {:error, bin} ->
        {:unfinished, bin, state}
    end
  end

  # Internal socket helpers

  defp socket_send({:sslsocket, _, _} = pid, bin) do
    # IO.puts("Sending #{byte_size(bin)} bytes")
    :ssl.send(pid, bin)
  end

  defp socket_send(pid, bin) do
    :gen_tcp.send(pid, bin)
  end

  defp setopts({:sslsocket, _, _} = pid, opts) do
    :ssl.setopts(pid, opts)
  end

  defp setopts(pid, opts) do
    :inet.setopts(pid, opts)
  end

  # handle_call

  def handle_call({:set_active, pid}, _from, state) do
    {:reply, :ok, %{state | active_user: pid}}
  end

  # Ignore if socket isn't established
  def handle_call({:send, _bin}, _from, %{socket: nil} = state) do
    {:reply, :ok, state}
  end

  def handle_call({:send, bin}, _from, state) when is_binary(bin) do
    resp = socket_send(state.socket, bin)
    {:reply, resp, state}
  end

  def handle_call({:send, bins}, _from, state) when is_list(bins) do
    for bin <- bins, do: socket_send(state.socket, bin)
    {:reply, :ok, state}
  end

  # handle_info

  def handle_info(:send_preface, state) do
    socket_send(state.socket, connection_preface())
    {:noreply, state}
  end

  def handle_info({:tcp, _socket, bin}, state) do
    do_recv_bin(bin, state)
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Kernel.send(state.active_user, {:closed, self()})
    {:noreply, %{state | socket: nil}}
  end

  def handle_info({:ssl, _socket, bin}, state) do
    do_recv_bin(bin, state)
  end

  def handle_info({:ssl_closed, _socket}, state) do
    Kernel.send(state.active_user, {:closed, self()})
    {:noreply, %{state | socket: nil}}
  end
end
