defmodule DosTest do
  use ExUnit.Case
  doctest Dos

  alias Dos.{Connection, Http2}

  test "GET https://http2.golang.org/" do
    uri = 'http2.golang.org'
    {:ok, pid} = Connection.start_link(uri)
  end
end
