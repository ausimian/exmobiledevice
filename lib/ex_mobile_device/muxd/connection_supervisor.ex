defmodule ExMobileDevice.Muxd.ConnectionSupervisor do
  @moduledoc false
  use DynamicSupervisor

  @spec start_link(any) :: Supervisor.on_start()
  def start_link(args) do
    DynamicSupervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @spec start_connection(Keyword.t()) :: DynamicSupervisor.on_start_child()
  def start_connection(args) do
    DynamicSupervisor.start_child(__MODULE__, {ExMobileDevice.Muxd.Connection, args})
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
