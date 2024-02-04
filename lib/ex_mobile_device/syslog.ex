defmodule ExMobileDevice.Syslog do
  alias ExMobileDevice.Services

  require Logger

  @syslog_relay "com.apple.syslog_relay"

  def open(udid) do
    with {:ok, ssl_sock} <- Services.connect(udid, @syslog_relay) do
      :ok = :ssl.setopts(ssl_sock, packet: 0)
      {:ok, ssl_sock}
    end
  end
end
