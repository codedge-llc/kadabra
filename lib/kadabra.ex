defmodule Kadabra do
  @moduledoc ~S"""
  HTTP/2 client for Elixir.

  Written to manage HTTP/2 connections for
  [pigeon](https://github.com/codedge-llc/pigeon).

  *Requires Elixir 1.4/OTP 19.2 or later.*

  ## Usage

  ```elixir
  {:ok, pid} = Kadabra.open("https://http2.golang.org")
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
  {:ok, pid} = Kadabra.open("https://http2.golang.org")

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

  alias Kadabra.{Connection, ConnectionQueue, Request, Stream, Supervisor}

  @typedoc ~S"""
  Options for connections.

  - `:ssl` - Specify custom options for `:ssl.connect/3`
    when used with `:https` scheme.
  - `:tcp` - Specify custom options for `:gen_tcp.connect/3`
    when used with `:http` scheme.
  """
  @type conn_opts :: [
          ssl: [...],
          tcp: [...]
        ]

  @typedoc ~S"""
  Options for making requests.

  - `:headers` - (Required) Headers for request.
  - `:body` - (Optional) Used for requests that can have a body, such as POST.
  - `:on_response` - (Optional) Async callback for handling stream response.
  """
  @type request_opts :: [
          headers: [{String.t(), String.t()}, ...],
          body: String.t(),
          on_response: (Stream.Response.t() -> no_return)
        ]

  @type uri :: charlist | String.t()

  @doc ~S"""
  Opens a new connection.

  ## Examples

      iex> {:ok, pid} = Kadabra.open("http://http2.golang.org")
      iex> is_pid(pid)
      true

      iex> {:ok, pid} = Kadabra.open("https://http2.golang.org")
      iex> is_pid(pid)
      true
  """
  @spec open(uri, conn_opts) :: {:ok, pid} | {:error, term}
  def open(uri, opts \\ [])

  def open(uri, opts) when is_binary(uri) do
    uri = URI.parse(uri)
    Supervisor.start_link(uri, self(), opts)
  end

  def open(uri, opts) when is_list(uri) do
    uri |> to_string() |> open(opts)
  end

  @doc ~S"""
  Closes an existing connection.

  ## Examples

      iex> {:ok, pid} = Kadabra.open("https://http2.golang.org")
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
    |> Connection.close()
  end

  @doc ~S"""
  Pings an existing connection.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('https://http2.golang.org')
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
    |> Connection.ping()
  end

  @doc ~S"""
  Makes a request with given headers and optional body.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('https://http2.golang.org')
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
  @spec request(pid, Request.t() | [Request.t()] | request_opts) :: no_return
  def request(pid, %Kadabra.Request{} = request) do
    ConnectionQueue.queue_request(pid, request)
  end

  def request(pid, [%Kadabra.Request{} | _rest] = requests) do
    ConnectionQueue.queue_request(pid, requests)
  end

  def request(pid, opts) when is_list(opts) do
    request = Kadabra.Request.new(opts)
    ConnectionQueue.queue_request(pid, request)
  end

  @doc ~S"""
  Makes a GET request.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('https://http2.golang.org')
      iex> Kadabra.head(pid, "/reqinfo")
      :ok
      iex> response = receive do
      ...>   {:end_stream, response} -> response
      ...> end
      iex> {response.id, response.status, response.body}
      {1, 200, ""}
  """
  @spec get(pid, String.t(), Keyword.t()) :: no_return
  def get(pid, path, opts \\ []) do
    request(pid, [{:headers, headers("GET", path)} | opts])
  end

  @doc ~S"""
  Makes a HEAD request.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('https://http2.golang.org')
      iex> Kadabra.head(pid, "/")
      :ok
      iex> response = receive do
      ...>   {:end_stream, response} -> response
      ...> end
      iex> {response.id, response.status, response.body}
      {1, 200, ""}
  """
  @spec head(pid, String.t(), Keyword.t()) :: no_return
  def head(pid, path, opts \\ []) do
    request(pid, [{:headers, headers("HEAD", path)} | opts])
  end

  @doc ~S"""
  Makes a POST request.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('https://http2.golang.org')
      iex> Kadabra.post(pid, "/", body: "test=123")
      :ok
      iex> response = receive do
      ...>   {:end_stream, response} -> response
      ...> end
      iex> {response.id, response.status}
      {1, 200}
  """
  @spec post(pid, String.t(), Keyword.t()) :: no_return
  def post(pid, path, opts \\ []) do
    request(pid, [{:headers, headers("POST", path)} | opts])
  end

  @doc ~S"""
  Makes a PUT request.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('https://http2.golang.org')
      iex> Kadabra.put(pid, "/crc32", body: "test")
      :ok
      iex> stream = receive do
      ...>   {:end_stream, stream} -> stream
      ...> end
      iex> stream.status
      200
      iex> stream.body
      "bytes=4, CRC32=d87f7e0c"
  """
  @spec put(pid, String.t(), Keyword.t()) :: no_return
  def put(pid, path, opts \\ []) do
    request(pid, [{:headers, headers("PUT", path)} | opts])
  end

  @doc ~S"""
  Makes a DELETE request.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('https://http2.golang.org')
      iex> Kadabra.delete(pid, "/")
      :ok
      iex> stream = receive do
      ...>   {:end_stream, stream} -> stream
      ...> end
      iex> stream.status
      200
  """
  @spec delete(pid, String.t(), Keyword.t()) :: no_return
  def delete(pid, path, opts \\ []) do
    request(pid, [{:headers, headers("DELETE", path)} | opts])
  end

  defp headers(method, path) do
    [
      {":method", method},
      {":path", path}
    ]
  end
end
