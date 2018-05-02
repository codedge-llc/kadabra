defmodule Kadabra.Request do
  @moduledoc ~S"""
  Struct to encapsulate Kadabra requests.

  Useful when queueing multiple requests at once through
  `Kadabra.request/2`
  """
  defstruct headers: [], body: nil, on_response: nil

  @type t :: %__MODULE__{
          headers: [],
          body: binary,
          on_response: (Response.t() -> no_return)
        }

  @doc ~S"""
  Returns a new `Kadabra.Request` struct from given opts.

  ## Examples

      iex> Kadabra.Request.new([
      ...>   headers: [{":method", "GET"}, {"path", "/"}],
      ...>   body: "",
      ...>   on_response: &IO.inspect/1
      ...> ])
      %Kadabra.Request{
        headers: [{":method", "GET"}, {"path", "/"}],
        body: "",
        on_response: &IO.inspect/1
      }
  """
  def new(opts) do
    %__MODULE__{
      headers: Keyword.get(opts, :headers, []),
      body: Keyword.get(opts, :body),
      on_response: Keyword.get(opts, :on_response)
    }
  end
end
