defmodule ExMobileDevice.Lockdown do
  @moduledoc """
  Communicates with `lockdownd`, an iOS daemon that holds system-wide
  information

  The connection with the daemon is represented by a process, returned
  by calling `connect/1`. The created process monitors the caller, exiting
  if the caller exits, unless `close/1` is called first.
  """
  use GenStateMachine, restart: :temporary
  use TypedStruct

  alias ExMobileDevice.Muxd
  alias ExMobileDevice.Services
  require Logger

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
    DynamicSupervisor.start_child(
      ExMobileDevice.Lockdown.Supervisor,
      {__MODULE__, udid: udid, controlling_process: self()}
    )
  end

  @doc """
  Close the `lockdownd` connection.
  """
  @spec close(pid()) :: :ok
  def close(conn) do
    GenStateMachine.stop(conn)
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
    args =
      Keyword.take(opts, [:domain, :key])
      |> Map.new(fn {k, v} -> {String.capitalize(to_string(k)), v} end)

    GenStateMachine.call(conn, {:get_value, args})
  end

  @doc """
  Start an authenticated session with lockdownd.

  On success, the connection process is now authenticated with the device
  and may perform privileged device operations such as retrieving sensitive
  information and/or starting further services.
  """
  @spec start_session(pid()) :: :ok | {:error, any}
  def(start_session(conn)) do
    GenStateMachine.call(conn, :start_session)
  end

  @doc """
  Terminate the current authenticated session.
  """
  @spec stop_session(pid) :: :ok | {:error, any}
  def stop_session(conn) do
    GenStateMachine.call(conn, :stop_session)
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
    GenStateMachine.call(conn, {:start_service, service, opts})
  end

  @lockdown_port 62_078

  @doc false
  def start_link(args) do
    GenStateMachine.start_link(__MODULE__, args)
  end

  typedstruct do
    @typedoc false
    field(:proc, pid())
    field(:sock, port())
    field(:sslsock, any())
    field(:mref, reference())
    field(:prec, map())
    field(:sid, binary() | nil)
  end

  @impl true
  def init(args) do
    proc = Keyword.fetch!(args, :controlling_process)
    udid = Keyword.fetch!(args, :udid)

    with {:ok, muxd} <- Muxd.connect(),
         {:ok, prec} <- maybe_get_pair_record(muxd, udid),
         {:ok, sock} <- Muxd.connect_thru(muxd, udid, @lockdown_port) do
      :ok = :inet.setopts(sock, packet: 4)

      ref = Process.monitor(proc)
      {:ok, :connected, %__MODULE__{sock: sock, mref: ref, prec: prec}}
    end
  end

  @impl true
  def handle_event({:call, from}, {:get_value, props}, _, %__MODULE__{} = data) do
    reply =
      with {:ok, response} <- Services.rpc(sock(data), "GetValue", props) do
        {:ok, response["Value"]}
      end

    {:keep_state_and_data, {:reply, from, reply}}
  end

  def handle_event({:call, from}, :start_session, _, %__MODULE__{prec: nil}) do
    {:keep_state_and_data, {:reply, from, {:error, :no_pairing_record}}}
  end

  def handle_event({:call, from}, :start_session, _, %__MODULE__{sid: sid})
      when not is_nil(sid) do
    {:keep_state_and_data, {:reply, from, {:error, :already_started}}}
  end

  def handle_event({:call, from}, :start_session, _, %__MODULE__{sid: nil, sslsock: nil} = data) do
    case Services.rpc(sock(data), "StartSession", Map.take(data.prec, ["SystemBUID", "HostID"])) do
      {:ok, %{"Request" => "StartSession", "EnableSessionSSL" => ssl?, "SessionID" => sid}} ->
        if ssl? do
          case ExMobileDevice.Ssl.connect(data.sock, data.prec) do
            {:ok, sslsock} ->
              {:keep_state, %__MODULE__{data | sslsock: sslsock, sid: sid}, {:reply, from, :ok}}
            error ->
              {:keep_state_and_data, {:reply, from, error}}
          end
        else
          {:keep_state, %__MODULE__{data | sid: sid}, {:reply, from, :ok}}
        end

      {:ok, %{"Request" => "StartSession", "Error" => error}} ->
        {:keep_state_and_data, {:reply, from, {:error, error}}}

      error ->
        Logger.error("#{__MODULE__}: Unexpected response from start session: #{inspect(error)}")
        {:keep_state_and_data, {:reply, from, {:error, :failed}}}
    end
  end

  def handle_event({:call, from}, :stop_session, _, %__MODULE__{sid: nil}) do
    {:keep_state_and_data, {:reply, from, {:error, :no_session}}}
  end

  def handle_event({:call, from}, :stop_session, _, %__MODULE__{sid: sid} = data) do
    {:ok, %{"Request" => "StopSession"}} =
      Services.rpc(sock(data), "StopSession", %{"SessionID" => sid})

    {:ok, sock} = :ssl.close(data.sslsock, {self(), :infinity})
    :ok = :inet.setopts(sock, packet: 4)
    {:keep_state, %__MODULE__{data | sid: nil, sslsock: nil, sock: sock}, {:reply, from, :ok}}
  end

  def handle_event({:call, from}, {:start_service, service, opts}, _, %__MODULE__{} = data) do
    if data.sid do
      keys = if Keyword.get(opts, :escrow, false), do: ["EscrowBag"], else: []
      args = Map.merge(%{"Service" => service}, Map.take(data.prec, keys))

      case Services.rpc(sock(data), "StartService", args) do
        {:ok, %{"Service" => ^service, "Port" => port} = reply} ->
          ssl? = !!reply["EnableServiceSSL"]
          {:keep_state_and_data, {:reply, from, {:ok, %{port: port, ssl: ssl?}}}}

        {:ok, %{"Error" => error}} ->
          {:keep_state_and_data, {:reply, from, {:error, error}}}

        error ->
          Logger.error("#{__MODULE__}: Unexpected response from start service: #{inspect(error)}")
          {:keep_state_and_data, {:reply, from, {:error, :failed}}}
      end
    else
      {:keep_state_and_data, {:reply, from, {:error, :no_session}}}
    end
  end

  def handle_event(:info, {:DOWN, ref, _, _, reason}, _, %__MODULE__{mref: ref}) do
    {:stop, reason}
  end

  defp maybe_get_pair_record(muxd, udid) do
    case Muxd.get_pair_record(muxd, udid) do
      {:ok, prec} ->
        {:ok, prec}

      _ ->
        {:ok, nil}
    end
  end

  defp sock(%__MODULE__{sock: sock, sslsock: sslsock}), do: if(sslsock, do: sslsock, else: sock)
end
