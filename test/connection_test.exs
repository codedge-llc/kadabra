defmodule Kadabra.ConnectionTest do
  use ExUnit.Case

  test "closes active streams on recv GOAWAY" do
    uri = 'https://http2.golang.org'
    {:ok, pid} = Kadabra.open(uri)

    # Open two streams that send the time every second
    Kadabra.get(pid, "/clockstream", on_response: & &1)
    Kadabra.get(pid, "/clockstream", on_response: & &1)

    {_, stream_sup_pid, _, _} =
      pid
      |> Supervisor.which_children()
      |> Enum.find(fn {name, _, _, _} -> name == :stream_sup end)

    {_, conn_sup_pid, _, _} =
      pid
      |> Supervisor.which_children()
      |> Enum.find(fn {name, _, _, _} -> name == :connection_sup end)

    {_, conn_pid, _, _} =
      conn_sup_pid
      |> Supervisor.which_children()
      |> Enum.find(fn {name, _, _, _} -> name == :connection end)

    # Wait to collect some data on the streams
    Process.sleep(500)

    assert Supervisor.count_children(stream_sup_pid).active == 2

    frame = Kadabra.Frame.Goaway.new(1)
    GenServer.cast(conn_pid, {:recv, frame})

    # Give a moment to clean everything up
    Process.sleep(500)

    receive do
      {:closed, _pid} ->
        assert Supervisor.count_children(stream_sup_pid).active == 0
    after
      5_000 -> flunk("Connection did not close")
    end
  end
end
