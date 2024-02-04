defmodule ExMobileDevice.Diagnostics do
  @moduledoc """
  Services for shutting down or restarting a device.
  """

  alias ExMobileDevice.TaskSupervisor
  alias ExMobileDevice.Services

  @diagnostics "com.apple.mobile.diagnostics_relay"

  @doc """
  Restart the specified device.
  """
  @spec restart(String.t()) :: :ok | {:error, any}
  def restart(udid) do
    run_in_task(udid, "Restart")
  end

  @doc """
  Shutdown the specified device.
  """
  @spec shutdown(String.t()) :: :ok | {:error, any}
  def shutdown(udid) do
    run_in_task(udid, "Shutdown")
  end

  @doc """
  Send the specified device to sleep.
  """
  @spec sleep(String.t()) :: :ok | {:error, any}
  def sleep(udid) do
    run_in_task(udid, "Sleep")
  end

  @doc false
  def ioreg(udid, opts \\ []) do
    args =
      opts
      |> Keyword.take([:current_plane, :entry_name, :entry_class])
      |> Map.new(fn {k, v} -> {to_ioreg_arg(k), v} end)

    run_in_task(fn ->
      with {:ok, ssl_sock} <- Services.connect(udid, @diagnostics) do
        case Services.rpc(ssl_sock, "IORegistry", args) do
          {:ok, %{"Status" => "Success"} = response} ->
            {:ok, get_in(response, ["Diagnostics", "IORegistry"])}

          _ ->
            {:error, :failed}
        end
      end
    end)
  end

  defp to_ioreg_arg(:current_plane), do: "CurrentPlane"
  defp to_ioreg_arg(:entry_class), do: "EntryClass"
  defp to_ioreg_arg(:entry_name), do: "EntryName"

  defp run_in_task(udid, request) when is_binary(request) do
    run_in_task(fn ->
      with {:ok, ssl_sock} <- Services.connect(udid, @diagnostics) do
        case Services.rpc(ssl_sock, request, %{}) do
          {:ok, %{"Status" => "Success"}} ->
            :ok

          _ ->
            {:error, :failed}
        end
      end
    end)
  end

  defp run_in_task(fun) when is_function(fun, 0) do
    task = TaskSupervisor.async_nolink(fun)
    {:ok, result} = Task.yield(task, :infinity) || Task.shutdown(task)
    result
  end
end
