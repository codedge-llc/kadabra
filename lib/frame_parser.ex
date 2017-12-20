defmodule Kadabra.FrameParser do
  @moduledoc false

  alias Kadabra.Frame
  alias Kadabra.Frame.{Data, Headers, RstStream, Settings, PushPromise,
    Ping, Goaway, WindowUpdate, Continuation}

  def parse(bin) do
    case Frame.new(bin) do
      {:ok, %{type: type} = frame, rest} ->
        mod = to_module(type)
        f = mod.new(frame)
        {:ok, f, rest}
      {:error, bin} ->
        {:error, bin}
    end
  end

  def to_module(0x0), do: Data
  def to_module(0x1), do: Headers
  def to_module(0x3), do: RstStream
  def to_module(0x4), do: Settings
  def to_module(0x5), do: PushPromise
  def to_module(0x6), do: Ping
  def to_module(0x7), do: Goaway
  def to_module(0x8), do: WindowUpdate
  def to_module(0x9), do: Continuation
end
