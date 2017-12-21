defmodule Kadabra.Request do
  defstruct headers: [], body: nil, on_response: nil

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
