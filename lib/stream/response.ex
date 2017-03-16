defmodule Kadabra.Stream.Response do
  @moduledoc """
  Struct returned from open connections.
  """
  defstruct id: nil, headers: nil, body: nil, status: nil

  def new(%Kadabra.Stream{id: id, headers: headers, body: body}) do
    %__MODULE__{
      id: id,
      headers: headers,
      body: body,
      status: get_status(headers)
    }
  end

  defp get_status(headers) do
    case Enum.find(headers, fn({key, _val}) -> key == ":status" end) do
      {":status", status} -> status |> String.to_integer
      nil -> nil
    end
  end
end
