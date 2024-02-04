defmodule ExMobileDevice.Muxd.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(args) do
    children = [
      {ExMobileDevice.Muxd.EventManager, []},
      {ExMobileDevice.Muxd.Monitor, args},
      {ExMobileDevice.Muxd.ConnectionSupervisor, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
