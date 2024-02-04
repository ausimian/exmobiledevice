defmodule ExMobileDevice.Services do
  @moduledoc false
  use TypedStruct

  alias ExMobileDevice.Muxd
  alias ExMobileDevice.Lockdown

  def connect(udid, service) do
    with {:ok, ldown} <- Lockdown.connect(udid),
         :ok <- Lockdown.start_session(ldown),
         {:ok, %{port: port, ssl: true}} <- Lockdown.start_service(ldown, service),
         {:ok, muxd} <- Muxd.connect(),
         {:ok, prec} <- Muxd.get_pair_record(muxd, udid),
         {:ok, sock} <- Muxd.connect_thru(muxd, udid, port),
         {:ok, ssl_sock} <- ExMobileDevice.Ssl.connect(sock, prec),
         :ok <- :ssl.setopts(ssl_sock, packet: 4) do
      {:ok, ssl_sock}
    end
  end

  def rpc(socket, request, props) do
    with {:ok, reply} <- send_and_receive(socket, encode(request, props)) do
      {:ok, Plist.decode(reply)}
    end
  end

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
