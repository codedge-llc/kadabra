defmodule KadabraTest do
  use ExUnit.Case
  doctest Dos

  alias Kadabra.{Connection, Http2}

  test "GET https://http2.golang.org/" do
    uri = 'http2.golang.org'
    {:ok, pid} = Connection.start_link(uri)
    headers = [
      {":method", "GET"},
      {":path", "/"},
      {"host", uri}
    ]
    GenServer.cast(pid, {:send, :headers, headers})
  end
end
