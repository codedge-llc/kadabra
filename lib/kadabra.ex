defmodule Kadabra do
  alias Kadabra.{Connection}

  def open(uri, scheme, opts \\ []) do
    Connection.start_link(uri, self, scheme: scheme, ssl: opts)
    receive do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    after 5_000 ->
      {:error, :timeout}
    end
  end

  def get(pid, path) do
		headers = [
			{":scheme", "https"},
			{":method", "GET"},
			{":path", path},
		]
		GenServer.cast(pid, {:send, :headers, headers})
  end
end
