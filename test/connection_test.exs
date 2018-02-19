defmodule Kadabra.ConnectionTest do
  use ExUnit.Case

  test "reconnects SSL socket automatically if disconnected" do
    uri = 'http2.golang.org'
    {:ok, pid} = Kadabra.open(uri, :https)

    {_, conn_pid, _, _} =
      pid
      |> Supervisor.which_children
      |> Enum.find(fn({name, _, _, _}) -> name == :connection end)

    %{socket: socket} = :sys.get_state(conn_pid)
    :ssl.close(socket)
    send(conn_pid, {:ssl_closed, socket}) # Why does close/1 not send this?

    Kadabra.ping(pid)

    assert_receive {:pong, _pid}, 5_000
  end

  test "closes active streams on recv GOAWAY" do
    uri = 'http2.golang.org'
    {:ok, pid} = Kadabra.open(uri, :https)

    # Open two streams that send the time every second
    Kadabra.get(pid, "/clockstream")
    Kadabra.get(pid, "/clockstream")

    {_, stream_sup_pid, _, _} =
      pid
      |> Supervisor.which_children()
      |> Enum.find(fn {name, _, _, _} -> name == :stream_sup end)

    {_, conn_pid, _, _} =
      pid
      |> Supervisor.which_children()
      |> Enum.find(fn {name, _, _, _} -> name == :connection end)

    # Wait to collect some data on the streams
    Process.sleep(1_500)

    assert Supervisor.count_children(stream_sup_pid).active == 2

    frame = Kadabra.Frame.Goaway.new(1)
    GenServer.cast(conn_pid, {:recv, frame})

    receive do
      {:closed, ^pid} ->
        # Give a moment to clean everything up
        Process.sleep(500)

        refute Process.alive?(stream_sup_pid)
        refute Process.alive?(pid)
    after
      5_000 -> flunk "Connection did not close"
    end
  end
end
