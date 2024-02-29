defmodule ExMobileDevice.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    muxd_config = Application.get_env(:exmobiledevice, ExMobileDevice.Muxd, [])

    children = [
      {ExMobileDevice.TaskSupervisor, []},
      {Registry, name: ExMobileDevice.Registry, keys: :unique},
      {ExMobileDevice.Muxd.Supervisor, muxd_config},
      {DynamicSupervisor, name: ExMobileDevice.Lockdown.Supervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: ExMobileDevice.WebInspector.Supervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: ExMobileDevice.FileConduit.Supervisor, strategy: :one_for_one}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExMobileDevice.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
