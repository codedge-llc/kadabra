defmodule Kadabra.Frame.Settings do
  @moduledoc false

  defstruct [:settings, ack: false]

  import Bitwise

  alias Kadabra.Connection

  @type t :: %__MODULE__{
          ack: boolean,
          settings: Connection.Settings.t() | nil
        }

  @spec ack :: t
  def ack do
    %__MODULE__{ack: true, settings: nil}
  end

  def new(%{payload: "", flags: flags}) do
    %__MODULE__{settings: nil, ack: ack?(flags)}
  end

  def new(%{payload: p, flags: flags}) do
    s_list = parse_settings(p)

    case put_settings(%Connection.Settings{}, s_list) do
      {:ok, settings} -> %__MODULE__{settings: settings, ack: ack?(flags)}
      {:error, code, _settings} -> {:error, code}
    end
  end

  @spec parse_settings(bitstring) :: [{char, non_neg_integer}, ...] | []
  defp parse_settings(<<>>), do: []

  defp parse_settings(bin) do
    <<identifier::16, value::32, rest::bitstring>> = bin
    [{identifier, value}] ++ parse_settings(rest)
  end

  defp put_settings(settings, []), do: {:ok, settings}

  defp put_settings(settings, [{ident, value} | rest]) do
    case Connection.Settings.put(settings, ident, value) do
      {:ok, settings} -> put_settings(settings, rest)
      {:error, code, settings} -> {:error, code, settings}
    end
  end

  @spec ack?(non_neg_integer) :: boolean
  defp ack?(flags) when (flags &&& 1) == 1, do: true
  defp ack?(_), do: false
end
