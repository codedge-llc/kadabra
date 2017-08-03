defmodule Kadabra.Stream do
  @moduledoc """
  Struct returned from open connections.
  """
  defstruct id: nil, headers: nil, body: nil, status: nil, error: nil
end
