defmodule Kadabra do
  @moduledoc """
    HTTP/2 client for Elixir.
  """
  alias Kadabra.{Connection}

  def open(uri, scheme, opts \\ []) do
    port = opts[:port] || 443
    nopts = List.keydelete opts, :port, 0
    case Connection.start_link(uri, self(), scheme: scheme, ssl: nopts, port: port) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  def close(pid), do: GenServer.cast(pid, {:send, :goaway})

  def ping(pid), do: GenServer.cast(pid, {:send, :ping})

  def request(pid, headers), do: GenServer.cast(pid, {:send, :headers, headers})
  def request(pid, headers, payload) do
    GenServer.cast(pid, {:send, :headers, headers, payload})
  end

  def get(pid, path) do
    headers = [
      {":method", "GET"},
      {":path", path},
    ]
    request(pid, headers)
  end

  def post(pid, path, payload) do
    headers = [
      {":method", "POST"},
      {":path", path},
    ]
    request(pid, headers, payload)
  end

  def put(pid, path, payload) do
    headers = [
      {":method", "PUT"},
      {":path", path},
    ]
    request(pid, headers, payload)
  end
end
