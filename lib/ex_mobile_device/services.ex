defmodule ExMobileDevice.Services do
  @moduledoc false
  use TypedStruct

  alias ExMobileDevice.Muxd
  alias ExMobileDevice.Lockdown

  @spec connect(String.t(), String.t()) :: {:ok, :ssl.sslsocket()} | {:error, any()}
  def connect(udid, service) do
    with {:ok, ldown} <- Lockdown.connect(udid),
         :ok <- Lockdown.start_session(ldown),
         {:ok, %{port: port} = info} <- Lockdown.start_service(ldown, service),
         :ok <- Lockdown.close(ldown),
         {:ok, muxd} <- Muxd.connect(),
         {:ok, prec} <- Muxd.get_pair_record(muxd, udid),
         {:ok, sock} <- Muxd.connect_thru(muxd, udid, port) do
      if info[:ssl] do
        with {:ok, ssl_sock} <- ExMobileDevice.Ssl.connect(sock, prec),
             :ok <- :ssl.setopts(ssl_sock, packet: 4) do
          {:ok, ssl_sock}
        end
      else
        {:ok, sock}
      end
    end
  end

  def rpc(socket, request) do
    plist =
      [
        ~s(<?xml version="1.0" encoding="UTF-8"?>),
        ?\n,
        ~s(<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">),
        ?\n,
        ExMobileDevice.Plist.encode(request)
      ]

    with {:ok, reply} <- send_and_receive(socket, plist) do
      {:ok, Plist.decode(reply)}
    end
  end

  def rpc(socket, request, props) do
    with {:ok, reply} <- send_and_receive(socket, encode(request, props)) do
      {:ok, Plist.decode(reply)}
    end
  end

  def send_plist(socket, request) do
    send_data(socket, ExMobileDevice.Plist.encode(request))
  end

  def recv_plist(socket) do
    with {:ok, data} <- recv_data(socket) do
      {:ok, Plist.decode(data)}
    end
  end

  defp send_data(sock, request) when is_port(sock), do: :gen_tcp.send(sock, request)
  defp send_data(sock, request) when is_tuple(sock), do: :ssl.send(sock, request)

  defp recv_data(sock) when is_port(sock), do: :gen_tcp.recv(sock, 0)
  defp recv_data(sock) when is_tuple(sock), do: :ssl.recv(sock, 0)

  defp send_and_receive(sock, data) when is_port(sock) do
    with :ok <- :gen_tcp.send(sock, data) do
      :gen_tcp.recv(sock, 0)
    end
  end

  defp send_and_receive(sock, data) when is_tuple(sock) do
    with :ok <- :ssl.send(sock, data) do
      :ssl.recv(sock, 0)
    end
  end

  defp encode(request, props) do
    %{"Label" => "exmobiledevice", "Request" => request}
    |> Map.merge(props)
    |> ExMobileDevice.Plist.encode()
  end
end
