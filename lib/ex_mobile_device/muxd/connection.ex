defmodule ExMobileDevice.Muxd.Connection do
  @moduledoc false
  use GenStateMachine, restart: :temporary
  use TypedStruct

  alias ExMobileDevice.Muxd.Socket

  @spec start_link(Keyword.t()) :: GenStateMachine.on_start()
  def start_link(args) do
    GenStateMachine.start_link(__MODULE__, args)
  end

  @spec get_pair_record(:gen_statem.server_ref(), binary()) :: {:ok, map()} | {:error, any}
  def get_pair_record(conn, udid) do
    GenStateMachine.call(conn, {:get_pair_record, udid})
  end

  @spec connect_thru(:gen_statem.server_ref(), binary(), non_neg_integer()) ::
          {:ok, port()} | {:error, any()}
  def connect_thru(conn, udid, port) do
    GenStateMachine.call(conn, {:connect_thru, udid, port})
  end

  @spec close(:gen_statem.server_ref()) :: :ok
  def close(conn) do
    GenStateMachine.stop(conn)
  end

  typedstruct do
    field(:controlling_process, pid())
    field(:monitor_ref, reference())
    field(:muxd, port())
  end

  @impl true
  def init(args) do
    addr = Keyword.fetch!(args, :addr)
    port = Keyword.fetch!(args, :port)
    proc = Keyword.fetch!(args, :controlling_process)

    case Socket.connect(addr, port) do
      {:ok, socket} ->
        ref = Process.monitor(proc)
        {:ok, :connected, %__MODULE__{controlling_process: proc, monitor_ref: ref, muxd: socket}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_event({:call, from}, {:connect_thru, udid, port}, _, %__MODULE__{} = data) do
    if did = ExMobileDevice.Muxd.Monitor.get_device_id(udid) do
      msg = %{"MessageType" => "Connect", "DeviceID" => did, "PortNumber" => htons(port)}

      case Socket.send_and_recv(data.muxd, msg, 0) do
        {:ok, %{"MessageType" => "Result", "Number" => 0}} ->
          :ok = :gen_tcp.controlling_process(data.muxd, elem(from, 0))
          {:stop_and_reply, :shutdown, {:reply, from, {:ok, data.muxd}}}

        {:ok, %{"MessageType" => "Result", "Number" => _}} ->
          {:keep_state_and_data, {:reply, from, {:error, :failed}}}

        error ->
          {:keep_state_and_data, {:reply, from, error}}
      end
    else
      {:keep_state_and_data, {:reply, from, {:error, :enoent}}}
    end
  end

  def handle_event({:call, from}, {:get_pair_record, udid}, _, %__MODULE__{} = data) do
    msg = %{"MessageType" => "ReadPairRecord", "PairRecordID" => udid}

    case Socket.send_and_recv(data.muxd, msg, 0) do
      {:ok, %{"PairRecordData" => record}} ->
        {:keep_state_and_data, {:reply, from, {:ok, Plist.decode(record)}}}

      {:ok, _} ->
        {:keep_state_and_data, {:reply, from, {:error, :enoent}}}

      _ ->
        {:keep_state_and_data, {:reply, from, {:error, :failed}}}
    end
  end

  def handle_event(:info, {:DOWN, ref, :process, pid, reason}, _, %__MODULE__{
        controlling_process: pid,
        monitor_ref: ref
      }) do
    {:stop, reason}
  end

  defp htons(hport) do
    <<nport::big-size(16)>> = <<hport::little-size(16)>>
    nport
  end
end
