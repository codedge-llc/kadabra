defmodule KadabraTest do
  use ExUnit.Case, async: true
  doctest Kadabra

  @moduletag report: [:pid]

  alias Kadabra.Stream

  @http2_uri "https://http2.codedge.dev"

  setup do
    pid =
      @http2_uri
      |> Kadabra.open()
      |> elem(1)

    [conn: pid]
  end

  describe "open/2" do
    @tag :golang
    test "sets port if specified", _context do
      opts = [port: 443]
      {:ok, pid} = Kadabra.open(@http2_uri, opts)

      conn_pid = :sys.get_state(pid).connection
      conn = :sys.get_state(conn_pid)

      assert conn.config.opts[:port] == 443
      Kadabra.close(pid)
    end
  end

  describe "request/2" do
    test "can take a list of requests", context do
      headers = [
        {":method", "GET"},
        {":path", "/"}
      ]

      request = Kadabra.Request.new(headers: headers)

      Kadabra.request(context[:conn], [request, request])

      for x <- [1, 3] do
        assert_receive {:end_stream, %Stream.Response{id: ^x}}, 5_000
      end
    end

    test "can take a single request", context do
      headers = [
        {":method", "GET"},
        {":path", "/"}
      ]

      request = Kadabra.Request.new(headers: headers)

      Kadabra.request(context[:conn], request)

      assert_receive {:end_stream, %Stream.Response{id: 1}}, 5_000
    end
  end

  describe "close/1" do
    test "sends close message and stops supervisor", context do
      pid = context[:conn]
      ref = Process.monitor(pid)
      Kadabra.close(pid)

      assert_receive {:closed, ^pid}, 5_000
      assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 5_000
    end
  end

  describe "GET" do
    test "can take an options keyword list", context do
      headers = [
        {":method", "GET"},
        {":path", "/"}
      ]

      Kadabra.request(context[:conn], headers: headers, on_response: & &1)

      assert_receive {:end_stream, %Stream.Response{id: 1}}, 5_000
    end

    test "https://http2.golang.org/healthz", context do
      Kadabra.get(context[:conn], "/healthz")

      receive do
        {:end_stream, response} ->
          assert response.id == 1
          assert response.status == 200
      after
        5_000 ->
          flunk("No stream response received.")
      end
    end

    test "https://http2.golang.org/healthz a lot", context do
      count = 1_000

      for _x <- 1..count do
        Kadabra.get(context[:conn], "/healthz")
      end

      is_odd = fn x -> rem(x, 2) == 1 end
      streams = 1..(2 * count) |> Enum.filter(&is_odd.(&1))

      for x <- streams do
        assert_receive {:end_stream, %Stream.Response{id: ^x}}, 30_000
      end
    end
  end

  describe "PUT" do
    test "https://http2.codedge.dev/ECHO", context do
      payload = String.duplicate("test", 10)
      Kadabra.put(context[:conn], "/ECHO", body: payload)

      expected_body = String.upcase(payload)

      receive do
        {:end_stream, response} ->
          assert response.id == 1
          assert response.status == 200
          assert response.body == expected_body
      after
        15_000 ->
          flunk("No stream response received.")
      end
    end

    test "https://http2.codedge.dev/ECHO with large payload", context do
      payload = String.duplicate("test", 100_000)
      Kadabra.put(context[:conn], "/ECHO", body: payload)

      expected_body = String.upcase(payload)

      receive do
        {:end_stream, response} ->
          assert response.id == 1
          assert response.status == 200
          assert response.body == expected_body
      after
        45_000 ->
          flunk("No stream response received.")
      end
    end
  end

  test "socket close message closes connection", _context do
    pid =
      @http2_uri
      |> Kadabra.open()
      |> elem(1)

    ref = Process.monitor(pid)

    conn_pid = :sys.get_state(pid).connection
    socket_pid = :sys.get_state(conn_pid).config.socket

    send(socket_pid, {:ssl_closed, nil})

    assert_receive {:closed, ^pid}, 5_000
    assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 5_000
  end
end
