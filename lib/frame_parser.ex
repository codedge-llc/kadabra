defmodule Kadabra.FrameParser do
  @moduledoc false

  alias Kadabra.Frame

  alias Kadabra.Frame.{
    Data,
    Headers,
    RstStream,
    Settings,
    PushPromise,
    Ping,
    Goaway,
    WindowUpdate,
    Continuation
  }

  def parse(bin) do
    case p(bin) do
      {:ok, frame, rest} ->
        {:ok, frame, rest}

      {:error, bin} ->
        {:error, bin}
    end
  end

  def p(""), do: {:error, ""}
  def p(<<p_size::24, type::8, f::8, 0::1, s_id::31, p::bitstring>> = bin) do
    size = p_size * 8
    if byte_size(bin) < (p_size + 9) do
      {:error, bin}
    else
      f_size = size + 72
      <<frame::size(f_size)>> <> rest = bin
      {:ok, <<frame::size(f_size)>>, <<rest::bitstring>>}
    end
  end

  def sid_and_type(<<_::24, type::8, _::8, 0::1, s_id::31, _::bitstring>>) do
    {s_id, type}
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
