defmodule Kadabra do
  @moduledoc """
  HTTP/2 client for Elixir.
  """
  alias Kadabra.{Connection, ConnectionQueue, Supervisor}

  @type uri :: charlist | String.t

  @doc ~S"""
  Opens a new connection.

  ## Examples

      iex> {:ok, pid} = Kadabra.open("http2.golang.org", :https)
      iex> is_pid(pid)
      true
  """
  @spec open(uri, :https, Keyword.t) :: {:ok, pid} | {:error, term}
  def open(uri, scheme, opts \\ []) do
    port = Keyword.get(opts, :port, 443)

    nopts =
      opts
      |> List.keydelete(:port, 0)

    start_opts = [scheme: scheme, ssl: nopts, port: port]

    Supervisor.start_link(uri, self(), start_opts)
  end

  @doc ~S"""
  Closes an existing connection.

  ## Examples

      iex> {:ok, pid} = Kadabra.open("http2.golang.org", :https)
      iex> Kadabra.close(pid)
      iex> receive do
      ...>   {:closed, _pid} -> "connection closed!"
      ...> end
      "connection closed!"
  """
  @spec close(pid) :: :ok
  def close(pid) do
    pid
    |> Connection.via_tuple
    |> GenServer.cast({:send, :goaway})
  end

  @doc ~S"""
  Pings an existing connection.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('http2.golang.org', :https)
      iex> Kadabra.ping(pid)
      iex> receive do
      ...>   {:pong, _pid} -> "got pong!"
      ...> end
      "got pong!"
  """
  @spec ping(pid) :: no_return
  def ping(pid) do
    pid
    |> Connection.via_tuple
    |> GenServer.cast({:send, :ping})
  end

  @doc ~S"""
  Makes a request with given headers.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('http2.golang.org', :https)
      iex> path = "/reqinfo" # Route echoes PUT body in uppercase
      iex> headers = [
      ...>   {":method", "GET"},
      ...>   {":path", path},
      ...> ]
      iex> Kadabra.request(pid, headers)
      iex> response = receive do
      ...>   {:end_stream, %Kadabra.Stream.Response{} = response} -> response
      ...> after 5_000 -> :timed_out
      ...> end
      iex> {response.id, response.status}
      {1, 200}
  """
  def request(pid, headers) do
    pid
    |> ConnectionQueue.via_tuple
    |> GenStage.call({:send, :headers, headers})
  end

  @doc ~S"""
  Makes a request with given headers and body.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('http2.golang.org', :https)
      iex> path = "/ECHO" # Route echoes PUT body in uppercase
      iex> body = "sample echo request"
      iex> headers = [
      ...>   {":method", "PUT"},
      ...>   {":path", path},
      ...> ]
      iex> Kadabra.request(pid, headers, body)
      iex> response = receive do
      ...>   {:end_stream, %Kadabra.Stream.Response{} = response} -> response
      ...> after 5_000 -> :timed_out
      ...> end
      iex> {response.id, response.status, response.body}
      {1, 200, "SAMPLE ECHO REQUEST"}
  """
  def request(pid, headers, body) do
    pid
    |> ConnectionQueue.via_tuple
    |> GenStage.call({:send, :headers, headers, body})
  end

  @doc ~S"""
  Makes a GET request.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('http2.golang.org', :https)
      iex> Kadabra.get(pid, "/reqinfo")
      :ok
      iex> response = receive do
      ...>   {:end_stream, response} -> response
      ...> end
      iex> {response.id, response.status}
      {1, 200}
  """
  @spec get(pid, String.t) :: no_return
  def get(pid, path) do
    request(pid, headers("GET", path))
  end

  @doc ~S"""
  Makes a HEAD request.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('http2.golang.org', :https)
      iex> Kadabra.head(pid, "/")
      :ok
      iex> response = receive do
      ...>   {:end_stream, response} -> response
      ...> end
      iex> {response.id, response.status, response.body}
      {1, 200, ""}
  """
  @spec head(pid, String.t) :: no_return
  def head(pid, path) do
    request(pid, headers("HEAD", path))
  end

  @doc ~S"""
  Makes a POST request.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('http2.golang.org', :https)
      iex> Kadabra.post(pid, "/", "test=123")
      :ok
      iex> response = receive do
      ...>   {:end_stream, response} -> response
      ...> end
      iex> {response.id, response.status}
      {1, 200}
  """
  @spec post(pid, String.t, any) :: no_return
  def post(pid, path, payload) do
    request(pid, headers("POST", path), payload)
  end

  @doc ~S"""
  Makes a PUT request.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('http2.golang.org', :https)
      iex> Kadabra.put(pid, "/crc32", "test")
      :ok
      iex> stream = receive do
      ...>   {:end_stream, stream} -> stream
      ...> end
      iex> stream.status
      200
      iex> stream.body
      "bytes=4, CRC32=d87f7e0c"
  """
  @spec put(pid, String.t, any) :: no_return
  def put(pid, path, payload) do
    request(pid, headers("PUT", path), payload)
  end

  @doc ~S"""
  Makes a DELETE request.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('http2.golang.org', :https)
      iex> Kadabra.delete(pid, "/")
      :ok
      iex> stream = receive do
      ...>   {:end_stream, stream} -> stream
      ...> end
      iex> stream.status
      200
  """
  @spec delete(pid, String.t) :: no_return
  def delete(pid, path) do
    request(pid, headers("DELETE", path))
  end

  defp headers(method, path) do
    [
      {":method", method},
      {":path", path},
    ]
  end
end
