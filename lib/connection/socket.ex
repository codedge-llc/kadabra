defmodule Kadabra.Connection.Socket do
  @moduledoc false

  @type ssl_sock :: {:sslsocket, any, pid | {any, any}}

  @type connection_result ::
          {:ok, ssl_sock}
          | {:ok, pid}
          | {:error, :not_implmenented}
          | {:error, :bad_scheme}

  @spec connect(URI.t(), Keyword.t()) :: connection_result
  def connect(uri, opts) do
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

  def send({:sslsocket, _, _} = pid, bin) do
    :ssl.send(pid, bin)
  end

  def send(pid, bin) do
    :gen_tcp.send(pid, bin)
  end

  def setopts({:sslsocket, _, _} = pid, opts) do
    :ssl.setopts(pid, opts)
  end

  def setopts(pid, opts) do
    :inet.setopts(pid, opts)
  end
end
