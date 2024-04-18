defmodule Kadabra.Connection.Egress do
  @moduledoc false

  alias Kadabra.{Encodable, Error, Frame, Socket}

  alias Kadabra.Frame.{
    Goaway,
    Ping,
    WindowUpdate
  }

  def send_goaway(socket, stream_id) do
    bin = stream_id |> Goaway.new() |> Encodable.to_bin()
    Socket.send(socket, bin)
  end

  def send_goaway(socket, stream_id, error, reason) do
    code = <<Error.code(error)::32>>

    bin =
      stream_id
      |> Goaway.new(code, reason)
      |> Encodable.to_bin()

    Socket.send(socket, bin)
  end

  def send_ping(socket) do
    bin = Ping.new() |> Encodable.to_bin()
    Socket.send(socket, bin)
  end

  def send_ping(socket, data) do
    bin = Ping.new(data) |> Encodable.to_bin()
    Socket.send(socket, bin)
  end

  def send_local_settings(socket, settings) do
    bin =
      %Frame.Settings{settings: settings}
      |> Encodable.to_bin()

    Socket.send(socket, bin)
  end

  @spec send_window_update(pid, non_neg_integer, integer) :: no_return
  def send_window_update(socket, stream_id, bytes)
      when bytes > 0 and bytes < 2_147_483_647 do
    bin =
      stream_id
      |> WindowUpdate.new(bytes)
      |> Encodable.to_bin()

    # Logger.info("Sending WINDOW_UPDATE on Stream #{stream_id} (#{bytes})")
    Socket.send(socket, bin)
  end

  def send_window_update(_socket, _stream_id, _bytes), do: :ok

  def send_settings_ack(socket) do
    bin = Frame.Settings.ack() |> Encodable.to_bin()
    Socket.send(socket, bin)
  end
end
