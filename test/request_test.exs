defmodule Kadabra.RequestTest do
  use ExUnit.Case
  doctest Kadabra.Request

  test "processes on_response on END_STREAM" do
    uri = 'http2.golang.org'
    pid = self()
    on_resp = fn _resp -> send(pid, :done) end

    {:ok, pid} = Kadabra.open(uri, :https)
    Kadabra.get(pid, "/reqinfo", on_response: on_resp)

    receive do
      :done -> :ok
    after
      5_000 -> flunk "No response callback message."
    end
  end
end
