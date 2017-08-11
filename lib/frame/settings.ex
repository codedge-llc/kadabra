defmodule Kadabra.Frame.Settings do
  @moduledoc false

  defstruct [:settings, ack: false]

  alias Kadabra.Connection
  alias Kadabra.Frame.Flags

  def new(%{payload: p, flags: flags}) do
    s_list = parse_settings(p)
    case put_settings(%Connection.Settings{}, s_list) do
      {:ok, settings} ->
        {:ok, %__MODULE__{settings: settings, ack: Flags.ack?(flags)}}
      {:error, code, _settings} -> {:error, code}
    end
  end

  def ack?(1), do: true
  def ack?(0), do: false

  def parse_settings(<<>>), do: []
  def parse_settings(bin) do
    <<identifier::16, value::32, rest::bitstring>> = bin
    [{identifier, value}] ++ parse_settings(rest)
  end

  def put_settings(settings, []), do: {:ok, settings}
  def put_settings(settings, [{ident, value} | rest]) do
    case Connection.Settings.put(settings, ident, value) do
      {:ok, settings} -> put_settings(settings, rest)
      {:error, code, settings} -> {:error, code, settings}
    end
  end
end

defimpl Kadabra.Encodable, for: Kadabra.Frame.Settings do
  alias Kadabra.Http2

  # TODO: Make this actually encode something
  def to_bin(_frame) do
    # ack = if frame.ack, do: Flags.ack, else: 0x0
    Http2.build_frame(0x4, 0x0, 0x0, <<>>)
  end
end
