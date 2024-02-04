defmodule ExMobileDevice.TaskSupervisor do
  @moduledoc false
  def child_spec(opts) do
    Task.Supervisor.child_spec(Keyword.put(opts, :name, __MODULE__))
  end

  def async_nolink(fun) do
    Task.Supervisor.async_nolink(__MODULE__, fun)
  end
end
