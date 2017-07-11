defmodule Kadabra do
  @moduledoc """
  HTTP/2 client for Elixir.
  """
  alias Kadabra.{Connection}

  def open(uri, scheme, opts \\ []) do
    port = opts[:port] || 443
    nopts = List.keydelete(opts, :port, 0)
    start_opts = [scheme: scheme, ssl: nopts, port: port]

    case Connection.start_link(uri, self(), start_opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  def close(pid), do: GenServer.cast(pid, {:send, :goaway})

  def ping(pid), do: GenServer.cast(pid, {:send, :ping})

  def info(pid, opts \\ []) do
    case GenServer.call(pid, :get_info) do
      {:ok, info} ->
        width = opts[:width] || 120
        headers = opts[:data] || [:id, :status, :headers, :body]
        stream_table_opts = [width: width, data: headers]

        stream_data =
          info.streams
          |> Map.values
          |> Enum.map(& Map.put(&1, :body, String.slice(&1.body, 0..40)))
          |> Enum.sort_by(& &1.id)
          |> Scribe.format(stream_table_opts)

        """

        == Connection Information ==
        Uri: #{info.uri}
        Scheme: #{info.scheme}
        Client: #{inspect(info.client)}
        SSL Socket: #{inspect(info.socket)}
        Next Available Stream ID: #{info.stream_id}
        Buffer: #{inspect(info.buffer)}

        == Streams ==
        #{stream_data}
        """
        |> IO.puts
      _else -> :error
    end
  end

  def request(pid, headers) do
    GenServer.cast(pid, {:send, :headers, headers})
  end

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

  @doc ~S"""
  Makes HTTP/2 PUT request.

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
