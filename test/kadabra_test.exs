defmodule KadabraTest do
  use ExUnit.Case

  alias Kadabra.{Connection, Http2, Stream}

  test "GET https://http2.golang.org/reqinfo" do
    uri = 'http2.golang.org'
    {:ok, pid} = Kadabra.open(uri, :https)
    Kadabra.get(pid, "/reqinfo")

    assert_receive {:end_stream, %Stream{
      id: 1,
      headers: headers,
      body: body,
      status: 200
    }}, 5_000
  end
end
