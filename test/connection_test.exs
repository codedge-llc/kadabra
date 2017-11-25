defmodule Kadabra.ConnectionTest do
  use ExUnit.Case

  test "reconnects SSL socket automatically if disconnected" do
    uri = 'http2.golang.org'
    {:ok, pid} = Kadabra.open(uri, :https)

    {_, sup_pid, _, _} =
      pid
      |> Supervisor.which_children
      |> Enum.find(fn({name, _, _, _}) -> name == :connection_sup end)

    {_, conn_pid, _, _} =
      sup_pid
      |> Supervisor.which_children
      |> Enum.find(fn({name, _, _, _}) -> name == :connection end)

    %{socket: socket} = :sys.get_state(conn_pid)
    :ssl.close(socket)
    send(conn_pid, {:ssl_closed, socket}) # Why does close/1 not send this?

    Kadabra.ping(pid)

    assert_receive {:pong, _pid}, 5_000
  end
end
