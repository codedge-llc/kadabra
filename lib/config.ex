defmodule Kadabra.Config do
  @moduledoc false

  defstruct client: nil,
            queue: nil,
            encoder: nil,
            decoder: nil,
            ref: nil,
            uri: nil,
            socket: nil,
            queue: nil,
            opts: []

  @type t :: %__MODULE__{
          client: pid,
          queue: pid,
          encoder: pid,
          decoder: pid,
          ref: term,
          uri: URI.t(),
          socket: pid,
          opts: Keyword.t()
        }
end
