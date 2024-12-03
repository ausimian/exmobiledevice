defmodule ExMobileDevice.FileConduit do
  @moduledoc false
  use GenServer, restart: :temporary
  use TypedStruct

  require Logger

  @service "com.apple.afc"

  @afcmagic "CFA6LPAA"
  @hdr_size 40

  @success 0x00
  @op_status 0x01
  @op_data 0x02
  @op_read_dir 0x03
  @op_rm_path 0x08
  @op_get_file_info 0x0A
  @op_file_open 0x0D
  @op_file_read 0x0F
  @op_file_write 0x10
  @op_file_close 0x14

  @mode_rdonly 0x01
  @mode_rw 0x02
  @mode_wronly 0x03
  @mode_wr 0x04
  @mode_append 0x05
  @mode_rdappend 0x06

  @modes %{
    "r" => @mode_rdonly,
    "r+" => @mode_rw,
    "w" => @mode_wronly,
    "w+" => @mode_wr,
    "a" => @mode_append,
    "a+" => @mode_rdappend
  }

  @max_read_size 4 * 1024 * 1024

  def start_supervised(udid, service) do
    child_spec = {__MODULE__, udid: udid, service: service, controlling_process: self()}
    DynamicSupervisor.start_child(ExMobileDevice.FileConduit.Supervisor, child_spec)
  end

  def list_dir(pid, path) do
    GenServer.call(pid, {:read_dir, path})
  end

  def stat(pid, path) do
    GenServer.call(pid, {:get_file_info, path})
  end

  def walk(pid, path) do
    GenServer.call(pid, {:walk, path}, :infinity)
  end

  def fopen(pid, path, mode \\ "r") when is_map_key(@modes, mode) do
    GenServer.call(pid, {:open, path, @modes[mode]})
  end

  def fread(pid, handle, size) do
    GenServer.call(pid, {:read, handle, min(size, @max_read_size)})
  end

  def fwrite(pid, handle, data) do
    GenServer.call(pid, {:write, handle, data})
  end

  def fclose(pid, handle) do
    GenServer.call(pid, {:close, handle})
  end

  def rm_rf(pid, path) do
    GenServer.call(pid, {:rm_rf, path})
  end

  def rm(pid, path) do
    GenServer.call(pid, {:rm, path})
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def stop(pid) do
    GenServer.stop(pid)
  end

  typedstruct do
    field(:sock, port() | :ssl.sslsocket())
    field(:cp, pid())
    field(:cp_ref, reference())
  end

  @impl true
  def init(args) do
    cp = Keyword.fetch!(args, :controlling_process)
    udid = Keyword.fetch!(args, :udid)
    service = Keyword.get(args, :service, @service)

    with {:ok, sock} <- ExMobileDevice.Services.connect(udid, service) do
      if is_port(sock) do
        :ok = :inet.setopts(sock, packet: 0)
      else
        :ok = :ssl.setopts(sock, packet: 0)
      end

      :erlang.put(:seqno, 0)
      ref = Process.monitor(cp)
      {:ok, %__MODULE__{sock: sock, cp: cp, cp_ref: ref}}
    end
  end

  @impl true
  def handle_call({:read_dir, path}, _from, %__MODULE__{sock: sock} = data) do
    {:reply, do_read_dir(sock, path), data}
  end

  def handle_call({:get_file_info, path}, _from, %__MODULE__{sock: sock} = data) do
    {:reply, do_stat(sock, path), data}
  end

  def handle_call({:walk, path}, _from, %__MODULE__{sock: sock} = data) do
    case do_stat(sock, path) do
      {:ok, _} ->
        {:reply, do_walk(sock, [path]), data}

      error ->
        {:reply, error, data}
    end
  end

  def handle_call({:open, path, mode}, _from, %__MODULE__{sock: sock} = data) do
    {:reply, do_open(sock, path, mode), data}
  end

  def handle_call({:read, handle, size}, _from, %__MODULE__{sock: sock} = data) do
    {:reply, do_read(sock, handle, size), data}
  end

  def handle_call({:write, handle, bytes}, _from, %__MODULE__{sock: sock} = data) do
    {:reply, do_write(sock, handle, bytes), data}
  end

  def handle_call({:close, handle}, _from, %__MODULE__{sock: sock} = data) do
    {:reply, do_close(sock, handle), data}
  end

  def handle_call({:rm_rf, path}, _from, %__MODULE__{sock: sock} = data) do
    {:reply, do_rmrf(sock, path), data}
  end

  def handle_call({:rm, path}, _from, %__MODULE__{sock: sock} = data) do
    {:reply, do_rm(sock, path), data}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, %__MODULE__{cp: pid, cp_ref: ref} = data) do
    {:stop, {:shutdown, reason}, data}
  end

  defp do_walk(sock, dirs) do
    files =
      Stream.unfold(dirs, fn
        [] ->
          nil

        [dir | rest] ->
          case do_read_dir(sock, dir) do
            {:ok, entries} ->
              {files, subdirs} =
                entries
                |> Enum.map(&Path.join(dir, &1))
                |> then(&split_by_type(sock, &1))

              {files, subdirs ++ rest}

            _ ->
              {[], rest}
          end
      end)

    {:ok, Enum.to_list(files) |> List.flatten() |> Enum.sort()}
  end

  defp split_by_type(sock, paths) do
    Enum.reduce(paths, {[], []}, fn path, {files, subdirs} ->
      case do_stat(sock, path) do
        {:ok, %File.Stat{type: :regular}} ->
          {[path | files], subdirs}

        {:ok, %File.Stat{type: :directory}} ->
          {files, [path | subdirs]}

        _ ->
          {files, subdirs}
      end
    end)
  end

  defp do_read_dir(sock, path) do
    case send_and_recv(sock, @op_read_dir, path) do
      {@success, response} ->
        paths =
          response
          |> :binary.split("\0", [:global, :trim])
          |> Enum.drop(2)

        {:ok, paths}

      {error_code, _} when is_integer(error_code) ->
        {:error, to_atom(error_code)}

      error ->
        error
    end
  end

  defp do_stat(sock, path) do
    case send_and_recv(sock, @op_get_file_info, path) do
      {@success, response} ->
        reply =
          response
          |> :binary.split("\0", [:global, :trim])
          |> Enum.chunk_every(2)
          |> Map.new(&List.to_tuple/1)
          |> then(&to_filestat/1)

        {:ok, reply}

      _ ->
        {:error, :enoent}
    end
  end

  def do_open(sock, path, mode) do
    request = [<<mode::unsigned-little-64>>, path]

    case send_and_recv(sock, @op_file_open, request) do
      {@success, <<handle::unsigned-little-64>>} ->
        {:ok, handle}

      {error_code, _} when is_integer(error_code) ->
        {:error, to_atom(error_code)}

      error ->
        error
    end
  end

  def do_read(sock, handle, size) do
    request = [<<handle::unsigned-little-64>>, <<size::unsigned-little-64>>]

    case send_and_recv(sock, @op_file_read, request) do
      {@success, data} ->
        {:ok, data}

      {error_code, _} when is_integer(error_code) ->
        {:error, to_atom(error_code)}

      error ->
        error
    end
  end

  defp do_write(sock, handle, data) do
    packet = [<<handle::unsigned-little-64>>, data]

    with :ok <- send_packet(sock, @op_file_write, packet, @hdr_size + 8),
         {num, <<>>} when is_integer(num) <- recv_packet(sock) do
      :ok
    end
  end

  def do_close(sock, handle) do
    request = <<handle::unsigned-little-64>>

    case send_and_recv(sock, @op_file_close, request) do
      {@success, <<>>} ->
        :ok

      {error_code, _} when is_integer(error_code) ->
        {:error, to_atom(error_code)}

      error ->
        error
    end
  end

  defp do_rmrf(sock, path), do: do_rmrf(sock, [], [path])

  defp do_rmrf(_, [], []), do: :ok
  defp do_rmrf(sock, [f|fs], dirs) do
    do_rm(sock, f)
    do_rmrf(sock, fs, dirs)
  end
  defp do_rmrf(sock, [], [dir | dirs] = ds) do
    case do_read_dir(sock, dir) do
      {:ok, []} ->
        do_rm(sock, dir)
        do_rmrf(sock, [], dirs)
      {:ok, entries} ->
        {files, subdirs} =
          entries
          |> Enum.map(&Path.join(dir, &1))
          |> then(&split_by_type(sock, &1))
        do_rmrf(sock, files, subdirs ++ ds)
      error ->
        error
    end
  end

  defp do_rm(_, "/"), do: :ok
  defp do_rm(sock, path) do
    case send_and_recv(sock, @op_rm_path, path) do
      {@success, ""} ->
        :ok

      {error_code, _} when is_integer(error_code) ->
        {:error, to_atom(error_code)}

      error ->
        error
    end
  end

  defp to_filestat(props) do
    ctime = :erlang.binary_to_integer(props["st_birthtime"]) |> DateTime.from_unix!(:nanosecond)
    mtime = :erlang.binary_to_integer(props["st_mtime"]) |> DateTime.from_unix!(:nanosecond)

    %File.Stat{
      access: :read,
      atime: mtime,
      mtime: mtime,
      ctime: ctime,
      uid: 0,
      gid: 0,
      mode: 0o644,
      inode: 0,
      links: :erlang.binary_to_integer(props["st_nlink"]),
      major_device: 0,
      minor_device: 0,
      size: :erlang.binary_to_integer(props["st_size"]),
      type: to_stat_type(props["st_ifmt"])
    }
  end

  defp to_stat_type("S_IFREG"), do: :regular
  defp to_stat_type("S_IFDIR"), do: :directory

  defp send_and_recv(sock, op, data, this_len \\ nil) do
    with :ok <- send_packet(sock, op, data, this_len) do
      recv_packet(sock)
    end
  end

  defp send_packet(sock, op, data, this_len) do
    do_send(sock, make_packet(op, data, this_len))
  end

  defp recv_packet(sock) do
    with {:ok, data} <- do_recv(sock, @hdr_size) do
      <<@afcmagic, total_len::unsigned-little-64, _::unsigned-64, _::unsigned-64,
        op::unsigned-little-64>> =
        data

      with {:ok, data} <- do_recv(sock, total_len - @hdr_size) do
        case op do
          @op_status ->
            <<status::unsigned-little-64>> = data
            {status, <<>>}

          @op_data ->
            {0, data}

          _ ->
            {0, data}
        end
      end
    end
  end

  defp make_packet(op, data, this_len) do
    total_len = IO.iodata_length(data) + @hdr_size
    this_len = this_len || total_len

    seqno = :erlang.get(:seqno)
    :erlang.put(:seqno, seqno + 1)

    [
      <<@afcmagic, total_len::unsigned-little-64, this_len::unsigned-little-64,
        seqno::unsigned-little-64, op::unsigned-little-64>>,
      data
    ]
  end

  defp do_send(sock, packet) when is_port(sock) do
    :gen_tcp.send(sock, packet)
  end

  defp do_send(sock, packet) when is_tuple(sock) do
    :ssl.send(sock, packet)
  end

  defp do_recv(sock, length) when is_port(sock) do
    :gen_tcp.recv(sock, length)
  end

  defp do_recv(sock, length) when is_tuple(sock) do
    :ssl.recv(sock, length)
  end

  defp to_atom(7), do: :badarg
  defp to_atom(8), do: :enoent
  defp to_atom(10), do: :eacces
  defp to_atom(n) when is_integer(n), do: :unknown
end
