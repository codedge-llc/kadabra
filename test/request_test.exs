defmodule Kadabra.RequestTest do
  use ExUnit.Case
  doctest Kadabra.Request

  test "processes on_response on END_STREAM" do
    uri = 'https://http2.golang.org'
    pid = self()
    on_resp = fn _resp -> send(pid, :done) end

    {:ok, pid} = Kadabra.open(uri)

    Kadabra.request("https://http2.golang.org/reqinfo",
      on_response: on_resp,
      to: pid
    )

    receive do
      :done -> :ok
    after
      5_000 -> flunk("No response callback message.")
    end
  end
end
