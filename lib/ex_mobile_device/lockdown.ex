defmodule ExMobileDevice.Lockdown do
  @moduledoc false

  alias ExMobileDevice.Services.Supervisor
  alias ExMobileDevice.Services.Lockdown

  @spec connect(String.t()) :: DynamicSupervisor.on_start_child()
  def connect(udid) when is_binary(udid) do
    Supervisor.start_child({Lockdown, udid: udid, controlling_process: self()})
  end

  def close(conn) do
    Lockdown.close(conn)
  end

  def get_info(conn, opts \\ []) do
    Lockdown.get_info(conn, opts)
  end

  def start_session(conn) do
    Lockdown.start_session(conn)
  end

  def stop_session(conn) do
    Lockdown.stop_session(conn)
  end

  def start_service(conn, service, opts \\ []) do
    Lockdown.start_service(conn, service, opts)
  end
end
