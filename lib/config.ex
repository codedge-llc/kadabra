defmodule Kadabra.Config do
  @moduledoc false

  defstruct client: nil,
            supervisor: nil,
            ref: nil,
            uri: nil,
            socket: nil,
            queue: nil,
            opts: []

  @type t :: %__MODULE__{
          client: pid,
          supervisor: pid,
          ref: term,
          uri: URI.t(),
          socket: pid,
          opts: Keyword.t()
        }
end
