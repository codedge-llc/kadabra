defmodule KadabraTest do
  use ExUnit.Case, async: true
  doctest Kadabra

  @moduletag report: [:pid]

  alias Kadabra.{Connection, Encodable, Frame, Stream}

  @golang_uri "https://http2.golang.org"

  setup do
    pid =
      @golang_uri
      |> Kadabra.open()
      |> elem(1)

    on_exit(fn ->
      Kadabra.close(pid)
    end)

    [conn: pid]
  end

  describe "open/2" do
    @tag :golang
    test "sets port if specified", _context do
      opts = [port: 443]
      {:ok, pid} = Kadabra.open(@golang_uri, opts)

      consumer =
        pid
        |> Connection.via_tuple()
        |> :sys.get_state()

      assert consumer.state.opts[:port] == 443
    end
  end

  describe "request/2" do
    @tag :golang
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

    @tag :golang
    test "can take a single request", context do
      headers = [
        {":method", "GET"},
        {":path", "/"}
      ]

      request = Kadabra.Request.new(headers: headers)

      Kadabra.request(context[:conn], request)

      assert_receive {:end_stream, %Stream.Response{id: 1}}, 5_000
    end

    @tag :golang
    test "can take an options keyword list", context do
      headers = [
        {":method", "GET"},
        {":path", "/"}
      ]

      Kadabra.request(context[:conn], headers: headers, on_response: & &1)

      assert_receive {:end_stream, %Stream.Response{id: 1}}, 5_000
    end
  end

  describe "GET" do
    @tag :golang
    test "https://http2.golang.org/reqinfo", context do
      Kadabra.get(context[:conn], "/reqinfo")

      receive do
        {:end_stream, response} ->
          assert response.id == 1
          assert response.status == 200
      after
        5_000 ->
          flunk("No stream response received.")
      end
    end

    @tag :golang
    test "https://http2.golang.org/reqinfo a lot", context do
      count = 5_000

      for _x <- 1..count do
        Kadabra.get(context[:conn], "/reqinfo")
      end

      is_odd = fn x -> rem(x, 2) == 1 end
      streams = 1..(2 * count) |> Enum.filter(&is_odd.(&1))

      for x <- streams do
        assert_receive {:end_stream, %Stream.Response{id: ^x}}, 30_000
      end
    end

    @tag :golang
    test "https://http2.golang.org/redirect", context do
      Kadabra.get(context[:conn], "/redirect")

      expected_body = "<a href=\"/\">Found</a>.\n\n"
      expected_status = 302

      receive do
        {:end_stream, response} ->
          assert response.id == 1
          assert response.status == expected_status
          assert response.body == expected_body
      after
        5_000 ->
          flunk("No stream response received.")
      end
    end

    @tag :golang
    test "https://http2.golang.org/file/gopher.png", context do
      Kadabra.get(context[:conn], "/file/gopher.png")

      receive do
        {:end_stream, response} ->
          assert response.id == 1
          assert response.status == 200
          assert byte_size(response.body) == 17668
      after
        5_000 ->
          flunk("No stream response received.")
      end
    end

    @tag :golang
    test "https://http2.golang.org/file/go.src.tar.gz", context do
      Kadabra.get(context[:conn], "/file/go.src.tar.gz")

      receive do
        {:end_stream, response} ->
          assert response.id == 1
          assert response.status == 200
          assert byte_size(response.body) == 10_921_353

        other ->
          IO.inspect(other)
          flunk("Unexpected response")
      after
        45_000 ->
          flunk("No stream response received.")
      end
    end

    @tag :golang
    test "https://http2.golang.org/serverpush", context do
      Kadabra.get(context[:conn], "/serverpush")

      receive do
        {:push_promise, response} ->
          assert response.id == 2
          refute response.status
          assert Stream.Response.get_header(response.headers, ":path")
      after
        5_000 ->
          flunk("No push promise received.")
      end
    end
  end

  describe "PUT" do
    @tag :golang
    test "https://http2.golong.org/ECHO", context do
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

    @tag :golang
    test "https://http2.golong.org/ECHO with large payload", context do
      payload = String.duplicate("test", 1_000_000)
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

    @tag :golang
    test "https://http2.golong.org/crc32", context do
      payload = "test"
      Kadabra.put(context[:conn], "/crc32", body: payload)

      expected_body = "bytes=4, CRC32=d87f7e0c"

      receive do
        {:end_stream, response} ->
          assert response.id == 1
          assert response.status == 200
          assert response.body == expected_body
      after
        5_000 ->
          flunk("No stream response received.")
      end
    end
  end

  test "GOAWAY frame closes connection", context do
    sup_pid = find_child(context[:conn], :connection_sup)
    conn_pid = find_child(sup_pid, :connection)

    bin = 1 |> Frame.Goaway.new() |> Encodable.to_bin()
    send(conn_pid, {:ssl, nil, bin})

    assert_receive {:closed, _pid}, 5_000
  end

  defp find_child(pid, name) do
    pid
    |> Supervisor.which_children()
    |> Enum.find(fn {n, _, _, _} -> n == name end)
    |> elem(1)
  end
end
