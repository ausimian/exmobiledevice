defmodule ExMobileDevice.Services.Lockdown do
  @moduledoc false
  use GenStateMachine, restart: :temporary
  use TypedStruct

  alias ExMobileDevice.Muxd
  alias ExMobileDevice.Services
  require Logger

  @lockdown_port 62_078

  def start_link(args) do
    GenStateMachine.start_link(__MODULE__, args)
  end

  def get_info(conn, opts \\ []) do
    args =
      Keyword.take(opts, [:domain, :key])
      |> Map.new(fn {k, v} -> {String.capitalize(to_string(k)), v} end)

    GenStateMachine.call(conn, {:get_value, args})
  end

  def start_session(conn) do
    GenStateMachine.call(conn, :start_session)
  end

  def stop_session(conn) do
    GenStateMachine.call(conn, :stop_session)
  end

  def start_service(conn, service, opts) do
    GenStateMachine.call(conn, {:start_service, service, opts})
  end

  def close(conn) do
    GenStateMachine.stop(conn)
  end

  typedstruct do
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
          {:ok, sslsock} = ExMobileDevice.Ssl.connect(data.sock, data.prec)

          {:keep_state, %__MODULE__{data | sslsock: sslsock, sid: sid}, {:reply, from, :ok}}
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
        {:ok, %{"Service" => ^service, "EnableServiceSSL" => ssl?, "Port" => port}} ->
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
