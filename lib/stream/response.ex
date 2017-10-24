defmodule Kadabra.Stream.Response do
  @moduledoc """
  Response struct returned from open streams.

  If received as a push promise, `:status` and `:body` will
  most likely be empty.

  *Sample response for a `PUT` request*

      %Kadabra.Stream.Response{
        body: "SAMPLE ECHO REQUEST",
        headers: [
          {":status", "200"},
          {"content-type", "text/plain; charset=utf-8"},
          {"date", "Sun, 16 Oct 2016 21:28:15 GMT"}
        ],
        id: 1,
        status: 200
      }
  """

  defstruct [:id, :headers, :body, :status]

  alias Kadabra.Stream

  @type t :: %__MODULE__{
    id: non_neg_integer,
    headers: Keyword.t,
    body: String.t,
    status: integer
  }

  @doc false
  @spec new(Stream.t) :: t
  def new(%Stream{id: id, headers: headers, body: body}) do
    %__MODULE__{
      id: id,
      headers: headers,
      body: body,
      status: get_status(headers)
    }
  end

  defp get_status(headers) do
    case get_header(headers, ":status") do
      {":status", status} -> status |> String.to_integer
      nil -> nil
    end
  end

  @doc ~S"""
  Fetches header with given name.

  ## Examples

      iex> stream = %Kadabra.Stream.Response{headers: [{":status", "200"}]}
      iex> Kadabra.Stream.Response.get_header(stream.headers, ":status")
      {":status", "200"}
  """
  @spec get_header([...], String.t) :: {String.t, term} | nil
  def get_header(headers, header) do
    headers
    |> Enum.filter(& &1 != :undefined)
    |> Enum.find(fn({key, _val}) -> key == header end)
  end
end
