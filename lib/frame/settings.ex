defmodule Kadabra.Frame.Settings do
  defstruct [:settings, ack: false]

  alias Kadabra.Connection

  def new(%{payload: p, flags: flags}) do
    s_list = parse_settings(p)
    case put_settings(%Connection.Settings{}, s_list) do
      {:ok, settings} ->
        {:ok, %__MODULE__{settings: settings, ack: ack?(flags)}}
      {:error, code, settings} -> {:error, code}
    end
  end

  def ack?(1), do: true
  def ack?(0), do: false

  def parse(payload) do
    settings = %Connection.Settings{}
  end

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
