defmodule Kadabra.Stream.Response do
  @moduledoc """
  Struct returned from open connections.
  """
  defstruct [:id, :headers, :body, :status]

  @type t :: %__MODULE__{
    id: integer,
    headers: Keyword.t,
    body: String.t,
    status: integer
  }

  @spec new(%Kadabra.Stream{}) :: t
  def new(%Kadabra.Stream{id: id, headers: headers, body: body}) do
    %__MODULE__{
      id: id,
      headers: headers,
      body: body,
      status: get_status(headers)
    }
  end

  defp get_status(headers) do
    result =
      headers
      |> Enum.filter(& &1 != :undefined)
      |> Enum.find(fn({key, _val}) -> key == ":status" end)

    case result do
      {":status", status} -> status |> String.to_integer
      nil -> nil
    end
  end
end
