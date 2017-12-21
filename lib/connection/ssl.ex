defmodule Kadabra.Connection.Ssl do
  @moduledoc false

  @type sock :: {:sslsocket, any, pid | {any, any}}

  @type connection_result :: {:ok, sock}
                           | {:error, :not_implmenented}
                           | {:error, :bad_scheme}

  @spec connect(charlist, Keyword.t) :: connection_result
  def connect(uri, opts) when is_binary(uri) do
    uri |> String.to_charlist |> connect(opts)
  end
  def connect(uri, opts) do
    case opts[:scheme] do
      :http -> {:error, :not_implemented}
      :https -> do_connect(uri, opts)
      _ -> {:error, :bad_scheme}
    end
  end

  defp do_connect(uri, opts) do
    :ssl.start()
    ssl_opts = options(Keyword.get(opts, :ssl, []))
    :ssl.connect(uri, opts[:port], ssl_opts)
  end

  @spec options(Keyword.t) :: [...]
  def options(opts) do
    opts ++ [
      {:active, :once},
      {:packet, :raw},
      {:reuseaddr, false},
      {:alpn_advertised_protocols, [<<"h2">>]},
      :binary
    ]
  end
end
