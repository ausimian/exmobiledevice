defmodule ExMobileDevice.Muxd do
  @moduledoc """
  Device management through `usbmuxd`.

  This module provides support for:

  - Listing the currently connected devices
  - Subscribing for device arrival/departure
  - Fetching the pairing record of a specified device
  - Starting, and connecting to, various device services

  """
  alias ExMobileDevice.Muxd.Monitor
  alias ExMobileDevice.Muxd.Connection
  alias ExMobileDevice.Muxd.ConnectionSupervisor

  @doc """
  List the currently connected devices.

  ## Example
      iex(1)> ExMobileDevice.Muxd.list_devices()
      []
      iex(2)> # Plug a device in!
      nil
      iex(3)> ExMobileDevice.Muxd.list_devices()
      ["00008120-0018DEADC0DEFACE"]
  """
  @spec list_devices() :: list(String.t())
  def list_devices() do
    Monitor.list_devices()
  end

  @doc """
  Subscribe for device arrival and departure.

  On success, this function returns the list of devices present at the
  time of subscription. Any device notifications received subsequently
  are guaranteed to have happened after this snapshot.

  The subscription is automatically removed when the subscriber exits.

  > #### Multiple subscriptions {: .info}
  >
  > Multiple subscriptions from the same process will result in duplicate
  > events being delivered to that process

  Device events are sent to the subscribing process and have the form:

  ```elixir
  {:exmobiledevice, {:device_attached, device_id}} # device arrivals
  {:exmobiledevice, {:device_detached, device_id}} # device departures
  ```

  Additionally, if the connection to `usbmuxd` itself is lost (or recovered),
  the subscribing process will receive the following messages:

  ```elixir
  {:exmobiledevice, :disconnected} # On disconnection
  {:exmobiledevice, :connected}    # On reconnection
  {:exmobiledevice, {:device_attached, device_id}} # For each connected device, on reconnection
  ```

  ## Example
      iex(1)> ExMobileDevice.Muxd.subscribe()
      {:ok, []}
      iex(2)> # Plug a device in!
      nil
      iex(3)> flush
      {:exmobiledevice, {:device_attached, "00008120-0018DEADC0DEFACE"}}
      :ok
      iex(4)> # Unplug the device!
      nil
      iex(5)> flush
      {:exmobiledevice, {:device_detached, "00008120-0018DEADC0DEFACE"}}
      :ok
  """
  @spec subscribe() :: {:ok, list(String.t())} | {:error, any()}
  def subscribe() do
    Monitor.subscribe()
  end

  @doc """
  Connect to `usbmuxd`.

  On success, a process is returned that encapsulates the connection and
  monitors the caller of this function, exiting if the caller exits.

  This process may be used to:

  - Retrieve pairing records from `usbmuxd`. See `get_pair_record/2`.
  - Start other services on the device
  - Connect to other services on the device. See `connect_thru/3`.

  ## Example
      iex(1)> ExMobileDevice.Muxd.connect()
      {:ok, #PID<0.212.0>}
  """
  @spec connect() :: DynamicSupervisor.on_start_child()
  def connect() do
    Application.get_env(:exmobiledevice, ExMobileDevice.Muxd)
    |> Keyword.put(:controlling_process, self())
    |> ConnectionSupervisor.start_connection()
  end

  @doc """
  Retrieve the pairing record for the specified device.

  ## Example
      iex(1)> {:ok, pid} = ExMobileDevice.Muxd.connect()
      {:ok, #PID<0.199.0>}
      iex(2)> ExMobileDevice.Muxd.get_pair_record(pid, "00008120-0018DEADC0DEFACE")
      {:ok,
      %{
        "DeviceCertificate" => "-----BEGIN CERTIFICATE----- ... elided ..."
      }}
  """
  @spec get_pair_record(:gen_statem.server_ref(), String.t()) :: {:ok, map()} | {:error, any}
  def get_pair_record(conn, udid) do
    Connection.get_pair_record(conn, udid)
  end

  @doc """
  Connect to the specified port on the specified device.

  On success, the connected socket is returned to the caller, and the caller becomes
  its [controlling process](https://www.erlang.org/doc/man/gen_tcp#controlling_process-2).

  > #### Conn shutdown {: .info}
  >
  > Once the underlying socket has been connected through to the specific device port
  > and returned to the caller, it can no longer be used to communicate with `usdbmuxd`
  > again and the process represented by `conn` will automatically stop after returning.

  ## Example
      iex(1)> {:ok, conn} = ExMobileDevice.Muxd.connect()
      {:ok, #PID<0.200.0>}
      iex(2)> {:ok, sock} = ExMobileDevice.Muxd.connect_thru(conn, "00008110-00180C36263B801E", 62078) # lockdownd
      {:ok, #Port<0.4>}
      iex(3)> Process.alive?(conn)
      false
  """
  @spec connect_thru(:gen_statem.server_ref(), String.t(), non_neg_integer()) ::
          {:ok, port()} | {:error, any()}
  def connect_thru(conn, udid, port) do
    Connection.connect_thru(conn, udid, port)
  end
end
