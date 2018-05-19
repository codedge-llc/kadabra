defmodule Kadabra.ConnectionTest do
  use ExUnit.Case

  test "closes active streams on socket close" do
    uri = 'https://http2.golang.org'
    {:ok, pid} = Kadabra.open(uri)

    IO.inspect(self(), label: "unit test")
    ref = Process.monitor(pid)

    # Open two streams that send the time every second
    Kadabra.get(pid, "/clockstream", on_response: & &1)
    Kadabra.get(pid, "/clockstream", on_response: & &1)

    {_, conn_pid, _, _} =
      pid
      |> Supervisor.which_children()
      |> Enum.find(fn {name, _, _, _} -> name == :connection end)

    {_, socket_pid, _, _} =
      pid
      |> Supervisor.which_children()
      |> Enum.find(fn {name, _, _, _} -> name == :socket end)

    # Wait to collect some data on the streams
    Process.sleep(500)

    state = :sys.get_state(conn_pid).state
    assert Enum.count(state.flow_control.stream_set.active_streams) == 2

    # frame = Kadabra.Frame.Goaway.new(1)
    # GenServer.cast(conn_pid, {:recv, frame})
    send(socket_pid, {:ssl_closed, nil})

    assert_receive {:closed, ^pid}, 5_000
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000
  end
end
