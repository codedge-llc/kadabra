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

  def get_status(headers) do
    case get_header(headers, ":status") do
      {":status", status} -> status |> String.to_integer
      nil -> nil
    end
  end

  def get_header(headers, header) do
    headers
    |> Enum.filter(& &1 != :undefined)
    |> Enum.find(fn({key, _val}) -> key == header end)
  end
end
