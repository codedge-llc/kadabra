defmodule Kadabra.Frame.PushPromise do
  defstruct [:stream_id, :headers, end_headers: false]
end
