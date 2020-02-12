defmodule Kadabra.ConnectionTest do
  use ExUnit.Case

  test "closes active streams on socket close" do
    uri = 'https://http2.golang.org'
    {:ok, pid} = Kadabra.open(uri)

    ref = Process.monitor(pid)

    # Open two streams that send the time every second
    Kadabra.get("https://http2.golang.org/clockstream",
      on_response: & &1,
      to: pid
    )

    Kadabra.get("https://http2.golang.org/clockstream",
      on_response: & &1,
      to: pid
    )

    conn_pid = :sys.get_state(pid).connection
    socket_pid = :sys.get_state(conn_pid).config.socket

    # Wait to collect some data on the streams
    Process.sleep(500)

    state = :sys.get_state(conn_pid)
    assert Enum.count(state.flow_control.stream_set.active_streams) == 2

    # frame = Kadabra.Frame.Goaway.new(1)
    # GenServer.cast(conn_pid, {:recv, frame})
    send(socket_pid, {:ssl_closed, nil})

    assert_receive {:closed, ^pid}, 5_000
    assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 5_000
  end
end
