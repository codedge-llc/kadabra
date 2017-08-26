defmodule Kadabra.ConnectionTest do
  use ExUnit.Case

  alias Kadabra.{Connection}

  test "reconnects SSL socket automatically if disconnected" do
    uri = 'http2.golang.org'
    {:ok, pid} = Kadabra.open(uri, :https)

    %{socket: socket} = :sys.get_state(pid)
    :ssl.close(socket)
    send(pid, {:ssl_closed, socket}) # Why does close/1 not send this?

    Kadabra.ping(pid)

    assert_receive {:pong, _pid}, 5_000
  end

  test "notifies active streams of settings updates" do
    uri = 'http2.golang.org'
    {:ok, pid} = Kadabra.open(uri, :https)
    conn = :sys.get_state(pid)

    old_window_size = Connection.Settings.default.initial_window_size
    new_window_size = 20_000

    old_settings = conn.flow_control.settings
    new_settings = %Connection.Settings{initial_window_size: new_window_size}
    new_flow =
      conn.flow_control
      |> Connection.FlowControl.add_active(1)
      |> Connection.FlowControl.update_settings(new_settings)

    {:ok, spid} = Kadabra.Supervisor.start_stream(conn, 1)
    {_state, stream} = :sys.get_state(spid)
    assert stream.flow.window == old_window_size

    Connection.notify_initial_window_change(conn.ref, old_settings, new_flow)

    {_state, stream} = :sys.get_state(spid)
    assert stream.flow.window == new_window_size
  end
end
