defmodule ExMobileDevice.Muxd.Socket do
  @moduledoc false

  alias Version.InvalidVersionError
  alias ExMobileDevice.Utils

  @protocol_version_plist 1
  @msgtype_plist 8

  def connect(addr, port) do
    with {:ok, socket} <- :gen_tcp.connect(addr, port, [:binary, active: false]) do
      case get_protocol_version(socket, 0) do
        {:ok, 1} ->
          {:ok, socket}

        {:ok, n} ->
          {:error, %InvalidVersionError{version: to_string(n)}}

        {:error, reason} ->
          {:error, %RuntimeError{message: inspect(reason)}}
      end
    end
  end

  def close(socket), do: :gen_tcp.close(socket)

  def request_events(socket, tag \\ 0) do
    case send_and_recv(socket, %{"MessageType" => "Listen"}, tag) do
      {:ok, %{"MessageType" => "Result", "Number" => 0}} ->
        :ok

      {:ok, %{"MessageType" => "Result", "Number" => _}} ->
        {:error, :failed}

      error ->
        error
    end
  end

  @spec parse_events(binary) :: Enumerable.t()
  def parse_events(bytes) do
    Stream.unfold(bytes, fn
      <<sz::little-32, @protocol_version_plist::little-32, @msgtype_plist::little-32,
        _::little-32, msg::binary-size(sz - 16), rest::binary>> ->
        {{:parsed, Plist.decode(msg)}, rest}

      rest when is_binary(rest) ->
        {{:partial, rest}, nil}

      nil ->
        nil
    end)
  end

  def send_and_recv(socket, request, tag) do
    with :ok <- send_request(socket, request, tag) do
      recv_response(socket, tag)
    end
  end

  defp send_request(socket, request, tag) do
    plist =
      Map.merge(
        %{
          "ClientVersionString" => "qt4i-usbmuxd",
          "ProgName" => "exmobiledevice",
          "kLibUSBMuxVersion" => 3
        },
        request
      )
      |> Utils.to_plist()

    header = <<@protocol_version_plist::little-32, @msgtype_plist::little-32, tag::little-32>>
    request = [<<4 + IO.iodata_length([plist, header])::little-size(32)>>, header, plist]
    :gen_tcp.send(socket, request)
  end

  defp recv_response(socket, tag) when is_integer(tag) do
    with {:ok, <<size::little-32>>} <- :gen_tcp.recv(socket, 4),
         {:ok, <<1::little-32, 8::little-32, ^tag::little-32, response::binary>>} <-
           :gen_tcp.recv(socket, size - 4) do
      {:ok, Plist.decode(response)}
    end
  end

  defp get_protocol_version(socket, tag) do
    header = <<
      @protocol_version_plist::little-32,
      @msgtype_plist::little-32,
      tag::little-32
    >>

    request = ExMobileDevice.Plist.encode(%{"MessageType" => "ReadBUID"})

    msg = [header, request]
    data = [<<4 + IO.iodata_length(msg)::little-32>> | msg]

    with :ok <- :gen_tcp.send(socket, data),
         {:ok, reply} <- :gen_tcp.recv(socket, 0) do
      <<size::little-32, version::little-32, @msgtype_plist::little-32, ^tag::little-32,
        _::binary-size(size - 16)>> = reply

      {:ok, version}
    end
  end
end
