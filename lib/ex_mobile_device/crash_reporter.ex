defmodule ExMobileDevice.CrashReporter do
  @moduledoc """
  Copy and clear crash logs from a device.
  """
  alias ExMobileDevice.TaskSupervisor
  alias ExMobileDevice.FileConduit

  @copy_service "com.apple.crashreportcopymobile"
  @read_size    1024 * 1024

  @doc """
  Copy crash reports from the specified device to the target directory.
  """
  @spec copy_crash_reports(String.t, Path.t) :: :ok | {:error, any()}
  def copy_crash_reports(udid, target_dir) do
    File.mkdir_p!(target_dir)
    run_in_task(fn -> copy_files_from_service(udid, target_dir) end)
  end

  @doc """
  Clear crash reports from the specified device.
  """
  @spec clear_crash_reports(String.t) :: :ok | {:error, any()}
  def clear_crash_reports(udid) do
    run_in_task(fn ->
      with {:ok, pid} <- FileConduit.start_supervised(udid, @copy_service) do
        FileConduit.rm_rf(pid, "/")
      end
    end)
  end

  defp copy_files_from_service(udid, target_dir) do
    with {:ok, pid} <- FileConduit.start_supervised(udid, @copy_service),
         {:ok, files} <- FileConduit.walk(pid, "/") do
      copy_files(files, pid, target_dir)
    end
  end

  defp copy_files([], pid, _), do: FileConduit.stop(pid)
  defp copy_files([file | rest], pid, target_dir) do
    target_file = Path.join(target_dir, file)
    with :ok <- File.mkdir_p(Path.dirname(target_file)),
         {:ok, local} <- File.open(target_file, [:raw, :binary, :write]),
         {:ok, remote} <- FileConduit.fopen(pid, file) do
      result = copy_file(pid, remote, local)
      FileConduit.fclose(pid, remote)
      File.close(local)

      case result do
        :ok ->
          copy_files(rest, pid, target_dir)
        error ->
          error
      end
    end
  end

  defp copy_file(pid, remote, local) do
    with {:ok, data} <- FileConduit.fread(pid, remote, @read_size) do
      :ok = IO.binwrite(local, data)
      if byte_size(data) == @read_size do
        copy_file(pid, remote, local)
      else
        :ok
      end
    end
  end

  defp run_in_task(fun) when is_function(fun, 0) do
    task = TaskSupervisor.async_nolink(fun)
    {:ok, result} = Task.yield(task, :infinity) || Task.shutdown(task)
    result
  end
end
