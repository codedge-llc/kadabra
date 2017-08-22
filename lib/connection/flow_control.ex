defmodule Kadabra.Connection.FlowControl do
  @moduledoc false

  defstruct queue: [],
            stream_id: 1,
            active_streams: 0,
            window: 65_535,
            settings: %Kadabra.Connection.Settings{}

  alias Kadabra.Connection

  @type t :: %__MODULE__{
    queue: [...],
    stream_id: pos_integer,
    active_streams: non_neg_integer,
    window: integer,
    settings: Connection.Settings.t
  }

  def put_settings(flow_control, settings) do
    %{flow_control | settings: settings}
  end

  @doc ~S"""
  Increments current `stream_id`.

  ## Examples

      iex> flow = %Kadabra.Connection.FlowControl{stream_id: 5}
      iex> increment_stream_id(flow)
      %Kadabra.Connection.FlowControl{stream_id: 7}
  """
  def increment_stream_id(flow_control) do
    %{flow_control | stream_id: flow_control.stream_id + 2}
  end

  @doc ~S"""
  Increments open stream count.

  ## Examples

      iex> flow = %Kadabra.Connection.FlowControl{active_streams: 2}
      iex> increment_active_stream_count(flow)
      %Kadabra.Connection.FlowControl{active_streams: 3}
  """
  def increment_active_stream_count(flow_control) do
    %{flow_control | active_streams: flow_control.active_streams + 1}
  end

  @doc ~S"""
  Decrements open stream count.

  ## Examples

      iex> flow = %Kadabra.Connection.FlowControl{active_streams: 2}
      iex> decrement_active_stream_count(flow)
      %Kadabra.Connection.FlowControl{active_streams: 1}
  """
  def decrement_active_stream_count(flow_control) do
    %{flow_control | active_streams: flow_control.active_streams - 1}
  end

  @doc ~S"""
  Increments available window.

  ## Examples

      iex> flow = %Kadabra.Connection.FlowControl{window: 1_000}
      iex> increment_window(flow, 500)
      %Kadabra.Connection.FlowControl{window: 1_500}
  """
  def increment_window(%{window: window} = flow_control, amount) do
    %{flow_control | window: window + amount}
  end

  @doc ~S"""
  Decrements available window.

  ## Examples

      iex> flow = %Kadabra.Connection.FlowControl{window: 1_000}
      iex> decrement_window(flow, 500)
      %Kadabra.Connection.FlowControl{window: 500}
  """
  def decrement_window(%{window: window} = flow_control, amount) do
    %{flow_control | window: window - amount}
  end

  @doc ~S"""
  Adds new sendable item to the queue.

  ## Examples

      iex> flow = %Kadabra.Connection.FlowControl{queue: []}
      iex> add(flow, "test", "payload")
      %Kadabra.Connection.FlowControl{queue: [{:send, "test", "payload"}]}
  """
  def add(%{queue: queue} = flow_control, headers, payload \\ nil) do
    %{flow_control | queue: queue ++ [{:send, headers, payload}]}
  end

  def process(%{queue: []} = flow_control, _connection) do
    flow_control
  end
  def process(%{queue: [{:send, headers, payload} | rest]} = flow,
              %{ref: ref} = connection) do
    if can_send?(flow) do
      {:ok, settings} = Kadabra.ConnectionSettings.fetch(ref)
      {:ok, pid} = Kadabra.Supervisor.start_stream(connection, settings)
      Registry.register(Registry.Kadabra, {ref, flow.stream_id}, pid)

      size = byte_size(payload || <<>>)
      :gen_statem.call(pid, {:send_headers, headers, payload})

      flow_control = %{flow | queue: rest}

      flow_control
      |> decrement_window(size)
      |> increment_active_stream_count()
      |> increment_stream_id()
    else
      flow
    end
  end

  @doc ~S"""
  Returns true if active_streams is less than max streams and window
  is positive.

  ## Examples

      iex> settings = %Kadabra.Connection.Settings{max_concurrent_streams: 100}
      iex> flow = %Kadabra.Connection.FlowControl{active_streams: 3,
      ...> window: 500, settings: settings}
      iex> can_send?(flow)
      true

      iex> settings = %Kadabra.Connection.Settings{max_concurrent_streams: 100}
      iex> flow = %Kadabra.Connection.FlowControl{active_streams: 3,
      ...> window: 0, settings: settings}
      iex> can_send?(flow)
      false

      iex> settings = %Kadabra.Connection.Settings{max_concurrent_streams: 1}
      iex> flow = %Kadabra.Connection.FlowControl{active_streams: 3,
      ...> window: 500, settings: settings}
      iex> can_send?(flow)
      false
  """
  def can_send?(%{active_streams: count, settings: settings, window: bytes}) do
    count < settings.max_concurrent_streams and bytes > 0
  end
end