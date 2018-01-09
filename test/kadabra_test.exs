defmodule KadabraTest do
  use ExUnit.Case
  doctest Kadabra

  @moduletag report: [:pid]

  alias Kadabra.{Connection, Encodable, Frame, Stream}

  describe "open/2" do
    @tag :golang
    test "sets port if specified" do
      uri = 'http2.golang.org'
      opts = [port: 443]
      {:ok, pid} = Kadabra.open(uri, :https, opts)

      consumer =
        pid
        |> Connection.via_tuple()
        |> :sys.get_state()

      assert consumer.state.opts[:port] == 443
    end
  end

  describe "GET" do
    @tag :golang
    test "https://http2.golang.org/reqinfo" do
      uri = 'http2.golang.org'
      {:ok, pid} = Kadabra.open(uri, :https)
      Kadabra.get(pid, "/reqinfo")

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
    test "https://http2.golang.org/reqinfo a lot" do
      uri = 'http2.golang.org'
      {:ok, pid} = Kadabra.open(uri, :https)

      count = 5_000

      for _x <- 1..count do
        Kadabra.get(pid, "/reqinfo")
      end

      is_odd = fn x -> rem(x, 2) == 1 end
      streams = 1..(2 * count) |> Enum.filter(&is_odd.(&1))

      for x <- streams do
        assert_receive {:end_stream, %Stream.Response{id: ^x}}, 30_000
      end
    end

    @tag :golang
    test "https://http2.golang.org/redirect" do
      uri = 'http2.golang.org'
      {:ok, pid} = Kadabra.open(uri, :https)
      Kadabra.get(pid, "/redirect")

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
    test "https://http2.golang.org/file/gopher.png" do
      uri = 'http2.golang.org'
      {:ok, pid} = Kadabra.open(uri, :https)
      Kadabra.get(pid, "/file/gopher.png")

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
    test "https://http2.golang.org/file/go.src.tar.gz" do
      uri = 'http2.golang.org'
      {:ok, pid} = Kadabra.open(uri, :https)
      Kadabra.get(pid, "/file/go.src.tar.gz")

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
    test "https://http2.golang.org/serverpush" do
      uri = 'http2.golang.org'
      {:ok, pid} = Kadabra.open(uri, :https)
      Kadabra.get(pid, "/serverpush")

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
    test "https://http2.golong.org/ECHO" do
      uri = 'http2.golang.org'
      {:ok, pid} = Kadabra.open(uri, :https)
      payload = String.duplicate("test", 10)
      Kadabra.put(pid, "/ECHO", body: payload)

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
    test "https://http2.golong.org/ECHO with large payload" do
      uri = 'http2.golang.org'
      {:ok, pid} = Kadabra.open(uri, :https)
      payload = String.duplicate("test", 1_000_000)
      Kadabra.put(pid, "/ECHO", body: payload)

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
    test "https://http2.golong.org/crc32" do
      uri = 'http2.golang.org'
      {:ok, pid} = Kadabra.open(uri, :https)
      payload = "test"
      Kadabra.put(pid, "/crc32", body: payload)

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

  test "GOAWAY frame closes connection" do
    uri = 'http2.golang.org'
    {:ok, pid} = Kadabra.open(uri, :https)

    sup_pid = find_child(pid, :connection_sup)
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
