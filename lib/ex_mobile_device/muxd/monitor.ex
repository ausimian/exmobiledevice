defmodule ExMobileDevice.Muxd.Monitor do
  @moduledoc false
  use GenStateMachine
  use TypedStruct

  alias ExMobileDevice.Muxd.EventManager
  alias ExMobileDevice.Muxd.Socket

  @spec start_link(Keyword.t()) :: :gen_statem.start_ret()
  def start_link(args) do
    GenStateMachine.start_link(__MODULE__, args, name: __MODULE__)
  end

  @spec list_devices() :: list(binary())
  def list_devices() do
    GenStateMachine.call(__MODULE__, :list_devices)
  end

  @spec subscribe() :: {:ok, list(binary())} | {:error, any()}
  def subscribe() do
    GenStateMachine.call(__MODULE__, :subscribe)
  end

  @spec get_device_id(binary) :: integer() | nil
  def get_device_id(udid) do
    :ets.lookup_element(__MODULE__, udid, 2, nil)
  end

  typedstruct do
    field(:addr, any())
    field(:port, non_neg_integer(), default: 0)
    field(:muxd, port() | nil)
    field(:partial, binary(), default: <<>>)
    field(:devices, %{integer() => String.t()}, default: %{})
  end

  @impl true
  def init(args) do
    addr = Keyword.fetch!(args, :addr)
    port = Keyword.fetch!(args, :port)
    data = %__MODULE__{addr: addr, port: port}

    :ets.new(__MODULE__, [:named_table])
    {:ok, :disconnected, data, retry_connect(0)}
  end

  @impl true
  def handle_event({:timeout, :connect}, _, :disconnected, %__MODULE__{} = data) do
    case Socket.connect(data.addr, data.port) do
      {:ok, socket} ->
        with :ok <- Socket.request_events(socket, 1),
             :ok = :inet.setopts(socket, active: :once) do
          EventManager.notify({:exmobiledevice, :connected})
          {:next_state, :connected, %__MODULE__{data | muxd: socket}}
        else
          _ ->
            Socket.close(socket)
            {:keep_state_and_data, retry_connect(1_000)}
        end

      _ ->
        {:keep_state_and_data, retry_connect(1_000)}
    end
  end

  def handle_event({:call, from}, :list_devices, _, %__MODULE__{} = data) do
    devices = Enum.sort(Map.values(data.devices))
    {:keep_state_and_data, {:reply, from, devices}}
  end

  def handle_event({:call, {pid, _} = from}, :subscribe, _state, %__MODULE__{} = data) do
    case EventManager.subscribe(pid) do
      :ok ->
        devices = Map.values(data.devices)
        {:keep_state_and_data, {:reply, from, {:ok, devices}}}

      error ->
        {:keep_state_and_data, {:reply, from, error}}
    end
  end

  def handle_event(:internal, {:parsed, %{} = msg}, _, %__MODULE__{} = data) do
    devices =
      case msg do
        %{"MessageType" => "Attached", "DeviceID" => device_id, "Properties" => props} ->
          if props["ConnectionType"] == "USB" do
            IO.inspect(msg)
            serial = props["SerialNumber"]
            EventManager.notify({:exmobiledevice, {:device_attached, serial}})
            :ets.insert(__MODULE__, {serial, device_id})
            Map.put(data.devices, device_id, serial)
          else
            data.devices
          end

        %{"MessageType" => "Detached", "DeviceID" => device_id} ->
          {serial, updated} = Map.pop(data.devices, device_id)

          unless is_nil(serial) do
            :ets.delete(__MODULE__, serial)
            EventManager.notify({:exmobiledevice, {:device_detached, serial}})
          end

          updated
      end

    {:keep_state, %__MODULE__{data | devices: devices}}
  end

  def handle_event(:internal, {:partial, bytes}, _, %__MODULE__{partial: <<>>} = data) do
    :ok = :inet.setopts(data.muxd, active: :once)
    {:keep_state, %__MODULE__{data | partial: bytes}}
  end

  def handle_event(:info, {:tcp, socket, packet}, :connected, %__MODULE__{muxd: socket} = data) do
    bytes = data.partial <> packet
    events = for e <- Socket.parse_events(bytes), do: {:next_event, :internal, e}
    {:keep_state, %__MODULE__{data | partial: <<>>}, events}
  end

  def handle_event(:info, {:tcp_closed, socket}, :connected, %__MODULE__{muxd: socket} = data) do
    disconnect(data)
  end

  def handle_event(:info, {:tcp_error, socket, _}, :connected, %__MODULE__{muxd: socket} = data) do
    disconnect(data)
  end

  defp disconnect(%__MODULE__{} = data) do
    Socket.close(data.muxd)
    EventManager.notify({:exmobiledevice, :disconnected})
    :ets.delete_all_objects(__MODULE__)
    {:next_state, :disconnected, %__MODULE__{addr: data.addr, port: data.port}, retry_connect(0)}
  end

  defp retry_connect(after_ms), do: {{:timeout, :connect}, after_ms, :connect}
end
