defmodule KadabraTest do
  use ExUnit.Case
  doctest Kadabra

  alias Kadabra.Stream

  describe "GET"  do
    test "https://http2.golang.org/reqinfo" do
      uri = 'http2.golang.org'
      {:ok, pid} = Kadabra.open(uri, :https)
      Kadabra.get(pid, "/reqinfo")

      assert_receive {:end_stream, %Stream.Response{
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

      assert_receive {:end_stream, %Stream.Response{
        id: 1,
        headers: _headers,
        body: ^expected_body,
        status: ^expected_status
      }}, 5_000
    end

    test "https://http2.golang.org/file/gopher.png" do
      uri = 'http2.golang.org'
      {:ok, pid} = Kadabra.open(uri, :https)
      Kadabra.get(pid, "/file/gopher.png")

      receive do
        {:end_stream, response} ->
          assert response.id == 1
          assert response.status == 200
          assert byte_size(response.body) == 17668
      after 5_000 ->
        flunk "No stream response received."
      end
    end

    test "https://http2.golang.org/serverpush" do
      uri = 'http2.golang.org'
      {:ok, pid} = Kadabra.open(uri, :https)
      Kadabra.get(pid, "/serverpush")

      receive do
        {:push_promise, response} ->
          assert response.id == 2
          refute response.status
          assert Stream.Response.get_header(response.headers, ":path")
      after 5_000 ->
        flunk "No push promise received."
      end
    end
  end

  describe "PUT" do
    test "https://http2.golong.org/ECHO" do
      uri = 'http2.golang.org'
      {:ok, pid} = Kadabra.open(uri, :https)
      payload = "test"
      Kadabra.put(pid, "/ECHO", payload)

      expected_body = String.upcase(payload)

      assert_receive {:end_stream, %Stream.Response{
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

      assert_receive {:end_stream, %Stream.Response{
        id: 1,
        headers: _headers,
        body: ^expected_body,
        status: 200
      }}, 5_000
    end
  end
end
