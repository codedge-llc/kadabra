defmodule Kadabra do
  @moduledoc """
  HTTP/2 client for Elixir.
  """
  alias Kadabra.{Connection}

  @doc ~S"""
  Opens a new connection.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('http2.golang.org', :https)
      iex> is_pid(pid)
      true
  """
  @spec open(charlist, :https, Keyword.t) :: {:ok, pid} | {:error, term}
  def open(uri, scheme, opts \\ []) do
    port = opts[:port] || 443
    reconnect = fetch_reconnect_option(opts)

    nopts =
      opts
      |> List.keydelete(:port, 0)
      |> List.keydelete(:reconnect, 0)
    start_opts = [scheme: scheme, ssl: nopts, port: port, reconnect: reconnect]

    case Connection.start_link(uri, self(), start_opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_reconnect_option(opts) do
    if List.keymember?(opts, :reconnect, 0) do
      opts[:reconnect]
    else
      true
    end
  end

  @doc ~S"""
  Closes an existing connection.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('http2.golang.org', :https)
      iex> Kadabra.close(pid)
      :ok
  """
  @spec close(pid) :: :ok
  def close(pid), do: GenServer.cast(pid, {:send, :goaway})


  @doc ~S"""
  Pings an existing connection.

  ## Examples

      iex> {:ok, pid} = Kadabra.open('http2.golang.org', :https)
      iex> Kadabra.ping(pid)
      iex> receive do
      ...>   {:pong, ^pid} -> "got pong!"
      ...> end
      "got pong!"
  """
  def ping(pid), do: GenServer.cast(pid, {:send, :ping})

  @doc false
  def info(pid, _opts \\ []) do
    case GenServer.call(pid, :get_info) do
      {:ok, info} ->
        # width = opts[:width] || 120
        # headers = opts[:data] || [:id, :status, :headers, :body]
        # stream_table_opts = [width: width, data: headers]

        # stream_data =
        #   info.streams
        #   |> Map.values
        #   |> Enum.map(& Map.put(&1, :body, String.slice(&1.body, 0..40)))
        #   |> Enum.sort_by(& &1.id)
        #   |> Scribe.format(stream_table_opts)

        """

        == Connection Information ==
        Uri: #{info.uri}
        Scheme: #{info.scheme}
        Client: #{inspect(info.client)}
        SSL Socket: #{inspect(info.socket)}
        Next Available Stream ID: #{info.stream_id}
        Buffer: #{inspect(info.buffer)}

        """
        |> IO.puts
      _else -> :error
    end
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
    GenServer.cast(pid, {:send, :headers, headers})
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
    GenServer.cast(pid, {:send, :headers, headers, body})
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
  def get(pid, path) do
    headers = [
      {":method", "GET"},
      {":path", path},
    ]
    request(pid, headers)
  end

  @doc ~S"""
  Makes a POST request.
  """
  def post(pid, path, payload) do
    headers = [
      {":method", "POST"},
      {":path", path},
    ]
    request(pid, headers, payload)
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
  def put(pid, path, payload) do
    headers = [
      {":method", "PUT"},
      {":path", path},
    ]
    request(pid, headers, payload)
  end
end
