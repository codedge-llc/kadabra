defmodule KadabraTest do
  use ExUnit.Case, async: true
  doctest Kadabra

  @moduletag report: [:pid]

  alias Kadabra.Stream

  @golang_uri "https://http2.golang.org"

  describe "open/2" do
    @tag :golang
    test "sets port if specified" do
      opts = [port: 443]
      {:ok, pid} = Kadabra.open(@golang_uri, opts)

      conn_pid = :sys.get_state(pid).connection
      conn = :sys.get_state(conn_pid)

      assert conn.config.opts[:port] == 443
      Kadabra.close(pid)
    end
  end

  def send_msg do
    p = self()
    fn response -> send(p, {:end_stream, response}) end
  end

  describe "request/2" do
    @tag :golang
    test "can take a list of requests" do
      headers = [
        {":method", "GET"},
        {":path", "/"}
      ]

      {:ok, pid} = Kadabra.open("https://http2.golang.org")
      request = Kadabra.Request.new(headers: headers, on_response: send_msg())

      Kadabra.request(pid, [request, request])

      for x <- [1, 3] do
        assert_receive {:end_stream, %Stream.Response{id: ^x}}, 5_000
      end
    end

    @tag :golang
    test "can take a single request" do
      headers = [
        {":method", "GET"},
        {":path", "/"}
      ]

      {:ok, pid} = Kadabra.open("https://http2.golang.org")
      request = Kadabra.Request.new(headers: headers, on_response: send_msg())

      Kadabra.request(pid, request)

      assert_receive {:end_stream, %Stream.Response{id: 1}}, 5_000
    end
  end

  describe "close/1" do
    test "sends close message and stops supervisor" do
      {:ok, pid} = Kadabra.open("https://http2.golang.org")
      ref = Process.monitor(pid)
      Kadabra.close(pid)

      assert_receive {:closed, ^pid}, 5_000
      assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 5_000
    end
  end

  describe "GET" do
    @tag :golang
    test "can take an options keyword list" do
      headers = [
        {":method", "GET"},
        {":path", "/"}
      ]

      {:ok, pid} = Kadabra.open("https://http2.golang.org")

      response = Kadabra.request(pid, headers: headers)
      assert response.id == 1
      assert response.body
      assert response.headers
    end

    @tag :golang
    test "https://http2.golang.org/reqinfo" do
      uri = "https://http2.golang.org/reqinfo"
      response = Kadabra.get(uri)

      assert response.status == 200
    end

    @tag :golang
    test "https://http2.golang.org/reqinfo a lot" do
      count = 5_000

      for _x <- 1..count do
        pid = self()

        Kadabra.get("https://http2.golang.org/reqinfo",
          on_response: fn response ->
            send(pid, {:end_stream, response})
          end
        )
      end

      is_odd = fn x -> rem(x, 2) == 1 end
      streams = 1..(2 * count) |> Enum.filter(&is_odd.(&1))

      for _x <- streams do
        assert_receive {:end_stream, %Stream.Response{}}, 30_000
      end
    end

    @tag :golang
    test "https://http2.golang.org/redirect" do
      uri = "https://http2.golang.org/redirect"
      response = Kadabra.get(uri)

      expected_body = "<a href=\"/\">Found</a>.\n\n"

      assert response.status == 302
      assert response.body == expected_body
    end

    @tag :golang
    test "https://http2.golang.org/file/gopher.png" do
      response = Kadabra.get("https://http2.golang.org/file/gopher.png")

      assert response.status == 200
      assert byte_size(response.body) == 17_668
    end

    @tag :golang
    test "https://http2.golang.org/file/go.src.tar.gz" do
      response =
        Kadabra.get("https://http2.golang.org/file/go.src.tar.gz",
          timeout: 45_000
        )

      assert response.status == 200
      assert byte_size(response.body) == 10_921_353
    end

    # @tag :golang
    # test "https://http2.golang.org/serverpush" do
    #   response =
    #     Kadabra.get("https://http2.golang.org/serverpush")
    #     |> IO.inspect()

    #   refute response.status
    #   assert rem(response.id, 2) == 0
    #   assert Stream.Response.get_header(response.headers, ":path")
    # end
  end

  describe "PUT" do
    @tag :golang
    test "https://http2.golong.org/ECHO" do
      payload = String.duplicate("test", 10)

      resp =
        Kadabra.put("https://http2.golang.org/ECHO",
          body: payload,
          timeout: 15_000
        )

      expected_body = String.upcase(payload)

      assert resp.status == 200
      assert resp.body == expected_body
    end

    @tag :golang
    test "https://http2.golong.org/ECHO with large payload" do
      payload = String.duplicate("test", 1_000_000)
      opts = [body: payload, timeout: 45_000]

      case Kadabra.put("https://http2.golang.org/ECHO", opts) do
        :timeout ->
          flunk("No stream response received.")

        response ->
          assert response.status == 200
          assert response.body == String.upcase(payload)
      end
    end

    @tag :golang
    test "https://http2.golong.org/crc32" do
      payload = "test"

      response = Kadabra.put("https://http2.golang.org/crc32", body: payload)

      expected_body = "bytes=4, CRC32=d87f7e0c"

      assert response.status == 200
      assert response.body == expected_body
    end
  end

  test "socket close message closes connection" do
    pid =
      @golang_uri
      |> Kadabra.open()
      |> elem(1)

    ref = Process.monitor(pid)

    conn_pid = :sys.get_state(pid).connection
    socket_pid = :sys.get_state(conn_pid).config.socket

    send(socket_pid, {:ssl_closed, nil})

    assert_receive {:closed, ^pid}, 5_000
    assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 5_000
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
