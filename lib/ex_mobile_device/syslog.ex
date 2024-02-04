defmodule ExMobileDevice.Syslog do
  @moduledoc """
  Reading syslogs.
  """
  alias ExMobileDevice.Services

  @syslog_relay "com.apple.syslog_relay"

  @doc """
  Connect to the raw syslog.

  On success, this function will return an (ssl) socket that can be read
  to retrieve the current syslog entries.

  > #### Raw syslog format {: .info}
  >
  > This function makes no attempt to parse the contents of the syslog.
  > The underlying transport is returned directly to the caller, who's
  > responsibility it is read the syslog stream.
  >
  > Each entry in the stream is a line terminated by _both_ a newline
  > and a NUL.

  """
  @spec open_raw(String.t()) :: {:ok, :ssl.sslsocket()} | {:error, any}
  def open_raw(udid) do
    with {:ok, ssl_sock} <- Services.connect(udid, @syslog_relay) do
      :ok = :ssl.setopts(ssl_sock, packet: 0)
      {:ok, ssl_sock}
    end
  end
end
