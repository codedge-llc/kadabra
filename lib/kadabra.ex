defmodule Kadabra do
  @moduledoc ~S"""
  HTTP/2 client for Elixir.

  Written to manage HTTP/2 connections for
  [pigeon](https://github.com/codedge-llc/pigeon).

  *Requires Elixir 1.4/OTP 19.2 or later.*

  ## Usage

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

  ## Making Requests Manually

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
  """

  import Supervisor.Spec

  alias Kadabra.{ConnectionPool, Request, Stream}

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
    spec_opts = [id: :erlang.make_ref(), restart: :transient]
    spec = worker(Kadabra.ConnectionPool, [uri, self(), opts], spec_opts)

    Supervisor.start_child(:kadabra, spec)
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
    Kadabra.ConnectionPool.close(pid)
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
    Kadabra.ConnectionPool.ping(pid)
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
      iex> me = self()
      iex> resp = & send(me, {:end_stream, &1})
      iex> Kadabra.request(pid, headers: headers, body: body, on_response: resp)
      iex> response = receive do
      ...>   {:end_stream, %Kadabra.Stream.Response{} = response} -> response
      ...> after 5_000 -> :timed_out
      ...> end
      iex> {response.id, response.status, response.body}
      {1, 200, "SAMPLE ECHO REQUEST"}
  """
  @spec request(pid, Request.t() | [Request.t()] | request_opts) :: no_return
  def request(pid, %Request{} = request) do
    ConnectionPool.request(pid, [request])
  end

  def request(pid, [%Request{} | _rest] = requests) do
    ConnectionPool.request(pid, requests)
  end

  def request(uri, opts) when is_list(opts) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    sync? = not Keyword.has_key?(opts, :on_response)

    request =
      opts
      |> Request.new()
      |> put_sync_response(sync?)

    case opts[:to] do
      nil -> Kadabra.Application.route_request(uri, request)
      pid -> Kadabra.Application.route_request(pid, request)
    end

    if sync? do
      receive do
        {:end_stream, response} -> response
        {:push_promise, response} -> response
      after
        timeout -> :timeout
      end
    else
      :ok
    end
  end

  @doc ~S"""
  Makes a GET request.

  ## Examples

      iex> response = Kadabra.get("https://http2.golang.org/reqinfo",
      ...> params: [something: 123])
      iex> response.status
      200
  """
  @spec get(String.t(), Keyword.t()) :: no_return
  def get(uri, opts \\ []) do
    uri = URI.parse(uri)
    path = encode_params(uri.path, opts)
    request(uri, [{:headers, headers("GET", path)} | opts])
  end

  @doc ~S"""
  Makes a HEAD request.

  ## Examples

      iex> response = Kadabra.head("https://http2.golang.org")
      iex> {response.status, response.body}
      {200, ""}
  """
  @spec head(String.t(), Keyword.t()) :: no_return
  def head(uri, opts \\ []) do
    uri = URI.parse(uri)
    path = encode_params(uri.path, opts)
    request(uri, [{:headers, headers("HEAD", path)} | opts])
  end

  @doc ~S"""
  Makes a POST request.

  ## Examples

      iex> response = Kadabra.post("https://http2.golang.org/", body: "test=123")
      iex> response.status
      200
  """
  @spec post(String.t(), Keyword.t()) :: no_return
  def post(uri, opts \\ []) do
    uri = URI.parse(uri)
    path = encode_params(uri.path, opts)
    request(uri, [{:headers, headers("POST", path)} | opts])
  end

  @doc ~S"""
  Makes a PUT request.

  ## Examples

      iex> response = Kadabra.put("https://http2.golang.org/crc32", body: "test")
      iex> {response.status, response.body}
      {200, "bytes=4, CRC32=d87f7e0c"}
  """
  @spec put(String.t(), Keyword.t()) :: no_return
  def put(uri, opts \\ []) do
    uri = URI.parse(uri)
    path = encode_params(uri.path, opts)
    request(uri, [{:headers, headers("PUT", path)} | opts])
  end

  @doc ~S"""
  Makes a DELETE request.

  ## Examples

      iex> response = Kadabra.delete("https://http2.golang.org/")
      iex> response.status
      200
  """
  @spec delete(String.t(), Keyword.t()) :: no_return
  def delete(uri, opts \\ []) do
    uri = URI.parse(uri)
    path = encode_params(uri.path, opts)
    request(uri, [{:headers, headers("DELETE", path)} | opts])
  end

  defp put_sync_response(request, true) do
    pid = self()
    Map.put(request, :on_response, &send(pid, {:end_stream, &1}))
  end

  defp put_sync_response(request, false), do: request

  defp encode_params(nil, opts), do: encode_params("/", opts)

  defp encode_params(path, opts) do
    case Keyword.get(opts, :params) do
      nil -> path
      params -> "#{path}?#{URI.encode_query(params)}"
    end
  end

  defp headers(method, path) do
    [
      {":method", method},
      {":path", path}
    ]
  end
end
