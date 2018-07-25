defmodule KadabraTest do
  use ExUnit.Case, async: true
  doctest Kadabra

  @moduletag report: [:pid]

  alias Kadabra.{Connection, Stream}

  @golang_uri "https://http2.golang.org"

  setup do
    pid =
      @golang_uri
      |> Kadabra.open()
      |> elem(1)

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

      assert consumer.state.config.opts[:port] == 443
      Kadabra.close(pid)
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
    @tag :golang
    test "can take an options keyword list", context do
      headers = [
        {":method", "GET"},
        {":path", "/"}
      ]

      Kadabra.request(context[:conn], headers: headers, on_response: & &1)

      assert_receive {:end_stream, %Stream.Response{id: 1}}, 5_000
    end

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
          assert byte_size(response.body) == 17_668
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
          flunk("Unexpected response: #{inspect(other)}")
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

  test "socket close message closes connection", _context do
    pid =
      @golang_uri
      |> Kadabra.open()
      |> elem(1)

    ref = Process.monitor(pid)

    conn_pid = find_child(pid, :connection)
    socket_pid = :sys.get_state(conn_pid).state.config.socket
    Process.sleep(500)

    send(socket_pid, {:ssl_closed, nil})

    assert_receive {:closed, ^pid}, 5_000
    assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 5_000
  end

  defp find_child(pid, name) do
    pid
    |> Supervisor.which_children()
    |> Enum.find(fn {n, _, _, _} -> n == name end)
    |> elem(1)
  end

  # @tag :golang
  # test "handles extremely large headers", _context do
  #   pid =
  #     "https://www.google.com"
  #     |> Kadabra.open()
  #     |> elem(1)

  #   big_str = String.duplicate("test", 5_000_000)

  #   # val = :hpack_integer.encode(byte_size(str), 7) |> IO.inspect(label: "size")

  #   request =
  #     Kadabra.Request.new(
  #       headers: [
  #         {":method", "GET"},
  #         {":path", "/"},
  #         # {"whatever", "yeah"}
  #         {"whatever", big_str}
  #       ]
  #     )

  #   Kadabra.request(pid, request)

  #   assert_receive {:end_stream, %Stream.Response{id: 1}}, 15_000
  # end
end
