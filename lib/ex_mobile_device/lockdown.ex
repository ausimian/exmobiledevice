defmodule ExMobileDevice.Lockdown do
  @moduledoc """
  Communicates with `lockdownd`, an iOS daemon that holds system-wide
  information

  The connection with the daemon is represented by a process, returned
  by calling `connect/1`. The created process monitors the caller, exiting
  if the caller exits, unless `close/1` is called first.
  """

  alias ExMobileDevice.Services.Supervisor
  alias ExMobileDevice.Services.Lockdown

  @doc """
  Connect to `lockdownd` on the specified device.

  On success, a process is returned that represents the connection to
  `lockdownd`. This process will exit when the caller exits, unless
  `close/1` is called first.

  ## Example
      iex(1)> ExMobileDevice.Lockdown.connect("00008120-0018DEADC0DEFACE")
      {:ok, #PID<0.303.0>}
  """
  @spec connect(String.t()) :: DynamicSupervisor.on_start_child()
  def connect(udid) when is_binary(udid) do
    Supervisor.start_child({Lockdown, udid: udid, controlling_process: self()})
  end

  @doc """
  Close the `lockdownd` connection.
  """
  @spec close(pid()) :: :ok
  def close(conn) do
    Lockdown.close(conn)
  end

  @doc """
  Retrieve data from `lockdownd`.

  The caller may provide the following options:
  - `:domain` - The domain of the query
  - `:key` - A specific key

  On success, the caller will return a map of the requested properties.

  If no session has yet been started on the connection (see
  `start_session/1`), only a very limited subset of properties will be
  returned.

  ## Example
      iex(1)> {:ok, conn} = ExMobileDevice.Lockdown.connect("00008120-0018DEADC0DEFACE")
      {:ok, #PID<0.303.0>}
      iex(2)> ExMobileDevice.Lockdown.get_info(conn)
      {:ok, %{
        # ... elided ...
      }}
  """
  @spec get_info(pid(), Keyword.t()) :: {:ok, %{String.t() => any()}} | {:error, any}
  def get_info(conn, opts \\ []) do
    Lockdown.get_info(conn, opts)
  end

  @doc """
  Start an authenticated session with lockdownd.

  On success, the connection process is now authenticated with the device
  and may perform privileged device operations such as retrieving sensitive
  information and/or starting further services.
  """
  @spec start_session(pid()) :: :ok | {:error, any}
  def(start_session(conn)) do
    Lockdown.start_session(conn)
  end

  @doc """
  Terminate the current authenticated session.
  """
  @spec stop_session(pid) :: :ok | {:error, any}
  def stop_session(conn) do
    Lockdown.stop_session(conn)
  end

  @doc """
  Start a service on the device.

  On success, the function returns a map containing the following keys:
  - `:port` - the port that the service is listening on
  - `:ssl` - a flag indicating whether an authenticated connection is required

  The caller should then establish _another_ connection to `usbmuxd` (via
  `ExMobileDevice.Muxd.connect/0`) and use this to connect through to the
  specified port (via `ExMobileDevice.Muxd.connect_thru/3`). If an authenticated
  connection is required, `ExMobileDevice.Ssl.connect/2` may be used to secure
  the connection

  This function requires that an authenticated session has already been
  started on the connection.

  Additional service-specific options may be passed in `opts`.

  ## Example
      iex(1)> {:ok, conn} = ExMobileDevice.Lockdown.connect("00008120-0018DEADC0DEFACE")
      {:ok, #PID<0.215.0>}
      iex(2)> ExMobileDevice.Lockdown.start_session(conn)
      :ok
      iex(3)> ExMobileDevice.Lockdown.start_service(conn, "com.apple.mobile.diagnostics_relay")
      {:ok, %{port: 50933, ssl: true}}
  """
  @spec start_service(pid(), String.t(), Keyword.t()) ::
          {:ok, %{port: integer(), ssl: boolean()}} | {:error, any()}
  def start_service(conn, service, opts \\ []) do
    Lockdown.start_service(conn, service, opts)
  end
end
