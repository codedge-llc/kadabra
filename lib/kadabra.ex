defmodule Kadabra do
  @moduledoc ~S"""
  HTTP/2 client for Elixir.

  Written to manage HTTP/2 connections for
  [pigeon](https://github.com/codedge-llc/pigeon).

  *Requires Elixir 1.4/OTP 19.2 or later.*

  ## Usage

  ```elixir
  {:ok, pid} = Kadabra.open('http2.golang.org', :https)
  Kadabra.get(pid, "/")
  receive do
    {:end_stream, %Kadabra.Stream.Response{} = stream} ->
    IO.inspect stream
  after 5_000 ->
    IO.puts "Connection timed out."
  end

  %Kadabra.Stream.Response{
    body: "<html>\\n<body>\\n<h1>Go + HTTP/2</h1>\\n\\n<p>Welcome to..."
    headers: [
      {":status", "200"},
      {"content-type", "text/html; charset=utf-8"},
      {"content-length", "1708"},
      {"date", "Sun, 16 Oct 2016 21:20:47 GMT"}
    ],
    id: 1,
    status: 200
  }
  ```

  ## Making Requests Manually

  ```elixir
  {:ok, pid} = Kadabra.open('http2.golang.org', :https)

  path = "/ECHO" # Route echoes PUT body in uppercase
  body = "sample echo request"
  headers = [
    {":method", "PUT"},
    {":path", path},
  ]

  Kadabra.request(pid, headers, body)

  receive do
    {:end_stream, %Kadabra.Stream.Response{} = stream} ->
    IO.inspect stream
  after 5_000 ->
    IO.puts "Connection timed out."
  end

  %Kadabra.Stream.Response{
    body: "SAMPLE ECHO REQUEST",
    headers: [
      {":status", "200"},
      {"content-type", "text/plain; charset=utf-8"},
      {"date", "Sun, 16 Oct 2016 21:28:15 GMT"}
    ],
    id: 1,
    status: 200
  }
  ```
  """

  alias Kadabra.{Connection, ConnectionQueue, Supervisor}
  alias Kadabra.Connection.Socket

  @typedoc ~S"""
  Options for connections.

  - `:port` - Override default port (80/443).
  - `:ssl` - Specify custom options for `:ssl.connect/3`
    when used with `:https` scheme.
  - `:tcp` - Specify custom options for `:gen_tcp.connect/3`
    when used with `:http` scheme.
  """
  @type conn_opts :: [
          port: pos_integer,
          ssl: [...],
          tcp: [...]
        ]

  @typedoc ~S"""
  Options for making requests.

  - `:headers` - (Required) Headers for request.
  - `:body` - (Optional) Used for requests that can have a body, such as POST.
  """
  @type request_opts :: [
          headers: [{String.t(), String.t()}, ...],
          body: String.t()
        ]

  @type scheme :: :http | :https

  @type uri :: charlist | String.t()

  @doc ~S"""
  Opens a new connection.

  ## Examples

      iex> {:ok, pid} = Kadabra.open("http2.golang.org", :http)
      iex> is_pid(pid)
      true

      iex> {:ok, pid} = Kadabra.open("http2.golang.org", :https)
      iex> is_pid(pid)
      true
  """
  @spec open(uri, scheme, conn_opts) :: {:ok, pid} | {:error, term}
  def open(uri, scheme, opts \\ []) do
    port = Socket.default_port(scheme)
    opts = Keyword.merge([scheme: scheme, port: port], opts)
    Supervisor.start_link(uri, self(), opts)
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
    |> Connection.via_tuple()
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
    |> Connection.via_tuple()
    |> GenServer.cast({:send, :ping})
  end

  @doc ~S"""
  Makes a request with given headers and optional body.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('http2.golang.org', :https)
      iex> path = "/ECHO" # Route echoes PUT body in uppercase
      iex> body = "sample echo request"
      iex> headers = [
      ...>   {":method", "PUT"},
      ...>   {":path", path},
      ...> ]
      iex> Kadabra.request(pid, headers: headers, body: body)
      iex> response = receive do
      ...>   {:end_stream, %Kadabra.Stream.Response{} = response} -> response
      ...> after 5_000 -> :timed_out
      ...> end
      iex> {response.id, response.status, response.body}
      {1, 200, "SAMPLE ECHO REQUEST"}
  """
  @spec request(pid, request_opts) :: no_return
  def request(pid, opts \\ []) do
    request = Kadabra.Request.new(opts)
    ConnectionQueue.queue_request(pid, request)
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
  @spec get(pid, String.t()) :: no_return
  def get(pid, path) do
    request(pid, headers: headers("GET", path))
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
  @spec head(pid, String.t()) :: no_return
  def head(pid, path) do
    request(pid, headers: headers("HEAD", path))
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
  @spec post(pid, String.t(), any) :: no_return
  def post(pid, path, payload \\ nil) do
    request(pid, headers: headers("POST", path), body: payload)
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
  @spec put(pid, String.t(), any) :: no_return
  def put(pid, path, payload \\ nil) do
    request(pid, headers: headers("PUT", path), body: payload)
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
  @spec delete(pid, String.t()) :: no_return
  def delete(pid, path) do
    request(pid, headers: headers("DELETE", path))
  end

  defp headers(method, path) do
    [
      {":method", method},
      {":path", path}
    ]
  end
end
