defmodule Kadabra.ConnectionTest do
  use ExUnit.Case

  test "closes active streams on socket close" do
    uri = 'https://http2.golang.org'
    {:ok, pid} = Kadabra.open(uri)

    ref = Process.monitor(pid)

    # Open two streams that send the time every second
    Kadabra.get(pid, "/clockstream", on_response: & &1)
    Kadabra.get(pid, "/clockstream", on_response: & &1)

    {_, stream_sup_pid, _, _} =
      pid
      |> Supervisor.which_children()
      |> Enum.find(fn {name, _, _, _} -> name == :stream_supervisor end)

    {_, conn_pid, _, _} =
      pid
      |> Supervisor.which_children()
      |> Enum.find(fn {name, _, _, _} -> name == :connection end)

    # Wait to collect some data on the streams
    Process.sleep(500)

    assert Supervisor.count_children(stream_sup_pid).active == 2

    # frame = Kadabra.Frame.Goaway.new(1)
    # GenServer.cast(conn_pid, {:recv, frame})
    send(conn_pid, {:ssl_closed, nil})

    assert_receive {:closed, ^pid}, 5_000
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000
  end
end
