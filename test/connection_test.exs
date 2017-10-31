defmodule Kadabra.ConnectionTest do
  use ExUnit.Case

  test "reconnects SSL socket automatically if disconnected" do
    uri = 'http2.golang.org'
    {:ok, pid} = Kadabra.open(uri, :https)

    %{socket: socket} = :sys.get_state(pid)
    :ssl.close(socket)
    send(pid, {:ssl_closed, socket}) # Why does close/1 not send this?

    Kadabra.ping(pid)

    assert_receive {:pong, _pid}, 5_000
  end
end
