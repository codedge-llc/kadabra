defmodule Dos.Connection do
  use GenServer
  require Logger

  alias Dos.Http2

  def start_link(uri) do
    GenServer.start_link(__MODULE__, {:ok, uri})
  end

  def init({:ok, uri}) do
    Logger.debug "Initing..."
    case do_connect(uri) do
      {:ok, socket} ->
        establish_connection(uri, socket)
      {:error, error} ->
        Logger.error(inspect(error))
        {:ok, %{}}
    end
  end

  def do_connect(uri) do
    options = [
               {:packet, :raw},
               {:reuseaddr, false},
               {:active, true},
               :binary]
    :ssl.start
    case :ssl.connect(uri, 443, options) do
      {:ok, ssl} -> 
        Logger.debug "Establishing connection..."
        :ssl.send(ssl, connection_preface)
        do_receive_once(ssl)
        :ssl.send(ssl, <<0, 0, 0>> <> <<0, 4>> <> <<0, 1>> <> <<0, 0, 0, 0>>)
        {:ok, ssl}
      {:error, reason} ->
        {:error, reason}
    end
		# case :gen_tcp.connect(uri, 80, [{:active, true}]) do
		# 	{:ok, sock} ->
    #     Logger.debug "ssl connect thing..."
    #       req = 
    #         """
    #         GET / HTTP/1.1
    #         Host: #{uri}
    #         Connection: Upgrade, HTTP2-Settings
    #         Upgrade: h2c
    #         HTTP2-Settings: AAAAAAQAAQAAAAA
    #         """
    #       :gen_tcp.send(sock, req)
    #       :gen_tcp.send(sock, connection_preface)

    #       :ssl.start
    #       case :ssl.connect(uri, 443, options) do
    #         {:ok, ssl} -> 
    #           Logger.debug "Establishing connection..."
    #           :ssl.send(ssl, connection_preface)
    #           :ssl.send(ssl, <<0, 0, 0>> <> <<0, 4>> <> <<0, 1>> <> <<0, 0, 0, 0>>)
    #           {:ok, ssl}
    #         {:error, reason} ->
    #           {:error, reason}
    #       end
    #     {:ok, sock}
		# 	{:error, reason} ->
    #     Logger.error "ssl connect thing..."
    #     {:error, reason}
		# end
  end

  defp do_receive_once _socket do
    receive do
      {:ssl, _socket, bin} ->
        Logger.debug bin
        {:ok, bin}
    end
  end

  def establish_connection(uri, socket) do
    state = %{
      socket: socket,
      stream_id: 1
    }

    #send_connection_preface(uri, socket)
    {:ok, state}
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

  def handle_info({:tcp, _socket, bin}, state) do
    Logger.debug("Recv TCP: #{inspect(bin)}")
    {:noreply, state}
  end

  def handle_info({:ssl, _socket, bin}, state) do
    Logger.debug("Recv SSL: #{inspect(bin)}")
    {:noreply, state}
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
