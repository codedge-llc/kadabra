defmodule Kadabra.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    Kadabra.Supervisor.start_link(name: :kadabra)
  end
end
