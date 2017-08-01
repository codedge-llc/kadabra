defmodule KadabraTest do
  use ExUnit.Case
  doctest Kadabra

  alias Kadabra.{Stream}

  describe "open/2" do
    test "sets reconnect option if specified" do
      uri = 'http2.golang.org'
      opts = [{:active, :once}, {:reconnect, false}, {:port, 443}, :binary]
      {:ok, pid} = Kadabra.open(uri, :https, opts)
      state = :sys.get_state(pid)
      refute state.reconnect
    end

    test "sets port if specified" do
      uri = 'http2.golang.org'
      opts = [{:active, :once}, {:reconnect, false}, {:port, 443}, :binary]
      {:ok, pid} = Kadabra.open(uri, :https, opts)
      state = :sys.get_state(pid)
      assert state.opts[:port] == 443
    end
  end

  describe "GET"  do
    test "https://http2.golang.org/reqinfo" do
      uri = 'http2.golang.org'
      {:ok, pid} = Kadabra.open(uri, :https)
      Kadabra.get(pid, "/reqinfo")

      assert_receive {:end_stream, %Stream{
        id: 1,
        headers: _headers,
        body: _body,
        status: 200
      }}, 5_000
    end

    test "https://http2.golang.org/redirect" do
      uri = 'http2.golang.org'
      {:ok, pid} = Kadabra.open(uri, :https)
      Kadabra.get(pid, "/redirect")

      expected_body = "<a href=\"/\">Found</a>.\n\n"
      expected_status = 302

      assert_receive {:end_stream, %Stream{
        id: 1,
        headers: _headers,
        body: ^expected_body,
        status: ^expected_status
      }}, 5_000
    end
  end

  describe "PUT" do
    test "https://http2.golong.org/ECHO" do
      uri = 'http2.golang.org'
      {:ok, pid} = Kadabra.open(uri, :https)
      payload = "test"
      Kadabra.put(pid, "/ECHO", payload)

      expected_body = String.upcase(payload)

      assert_receive {:end_stream, %Stream{
        id: 1,
        headers: _headers,
        body: ^expected_body,
        status: 200
      }}, 5_000
    end

    test "https://http2.golong.org/crc32" do
      uri = 'http2.golang.org'
      {:ok, pid} = Kadabra.open(uri, :https)
      payload = "test"
      Kadabra.put(pid, "/crc32", payload)

      expected_body = "bytes=4, CRC32=d87f7e0c"

      assert_receive {:end_stream, %Stream{
        id: 1,
        headers: _headers,
        body: ^expected_body,
        status: 200
      }}, 5_000
    end
  end
end
