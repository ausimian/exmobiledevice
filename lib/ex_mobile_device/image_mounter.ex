defmodule ExMobileDevice.ImageMounter do
  @moduledoc """
  Functions for dealing with developer disk images.
  """
  @service "com.apple.mobile.mobile_image_mounter"
  @tss "https://gs.apple.com/TSS/controller?action=2"

  alias ExMobileDevice.TaskSupervisor
  alias ExMobileDevice.Services

  @doc """
  Unmount the disk at the specified path.
  """
  @spec unmount(String.t(), Path.t()) :: :ok | {:error, any()}
  def unmount(udid, mount_path) do
    request = %{"Command" => "UnmountImage", "MountPath" => mount_path}

    case run_in_task(udid, request) do
      {:ok, %{"Status" => "Complete"}} ->
        :ok

      {:ok, not_completed} ->
        {:error, not_completed}

      error ->
        error
    end
  end

  @doc """
  Fetch a signature for the specified device.
  """
  @spec fetch_manifest_from_tss(String.t(), Path.t()) :: {:ok, binary()} | {:error, any()}
  def fetch_manifest_from_tss(udid, build_manifest_path) do
    run_in_task(fn ->
      {:ok, ssl_sock} = Services.connect(udid, @service)
      get_manifest_from_tss(ssl_sock, Plist.decode(File.read!(build_manifest_path)))
    end)
  end

  @doc """
  Mount a developer disk for a pre-iOS17 device.
  """
  @spec mount(String.t(), Path.t(), Path.t()) :: :ok | {:error, any()}
  def mount(udid, image_path, sig_path) do
    result =
      run_in_task(fn ->
        with {:ok, image} <- File.read(image_path),
             {:ok, signature} <- File.read(sig_path),
             {:ok, ssl_sock} <- Services.connect(udid, @service),
             :ok <- upload_image(ssl_sock, "DeveloperDiskImage", image, signature) do
          mount_image(ssl_sock, "Developer", signature, %{})
        end
      end)

    case result do
      {:ok, %{"Status" => "Complete"}} ->
        :ok

      {:ok, not_completed} ->
        {:error, not_completed}

      error ->
        error
    end
  end

  @doc """
  Mount a developer disk for an iOS 17+ device.
  """
  @spec mount(String.t(), Path.t(), Path.t(), Path.t(), map() | nil) :: :ok | {:error, any()}
  def mount(udid, image_path, build_manifest_path, trust_cache_path, info_plist \\ nil) do
    result =
      run_in_task(fn ->
        image = File.read!(image_path)
        signature = :crypto.hash(:sha384, image)

        {:ok, ssl_sock} = Services.connect(udid, @service)

        {:ok, ssl_sock, manifest} =
          case query_personalization_manifest(ssl_sock, signature) do
            {:ok, %{"ImageSignature" => manifest}} ->
              {:ok, ssl_sock, manifest}

            _ ->
              {:ok, ssl_sock} = Services.connect(udid, @service)

              {:ok, manifest} =
                get_manifest_from_tss(ssl_sock, Plist.decode(File.read!(build_manifest_path)))

              {:ok, ssl_sock, manifest}
          end

        :ok = upload_image(ssl_sock, "Personalized", image, manifest)

        # ssl_sock
        extras = if info_plist, do: %{"ImageInfoPlist" => info_plist}, else: %{}
        extras = Map.put(extras, "ImageTrustCache", {:data, File.read!(trust_cache_path)})
        mount_image(ssl_sock, "Personalized", manifest, extras)
      end)

    case result do
      {:ok, %{"Status" => "Complete"}} ->
        :ok

      {:ok, not_completed} ->
        {:error, not_completed}

      error ->
        error
    end
  end

  @doc """
  List mounts on the target device.
  """
  @spec list_mounted(String.t()) :: {:ok, list(map())} | {:error, any()}
  def list_mounted(udid) do
    case run_in_task(udid, %{"Command" => "CopyDevices"}) do
      {:ok, %{"EntryList" => list}} ->
        {:ok, list}

      _ ->
        {:error, :failed}
    end
  end

  @doc """
  Look up the signature of the specified image.
  """
  @spec lookup_image_signature(String.t(), String.t()) :: {:ok, binary()} | {:error, any()}
  def lookup_image_signature(udid, type) when type in ["Developer", "Personalized"] do
    case run_in_task(udid, %{"Command" => "LookupImage", "ImageType" => type}) do
      {:ok, %{"ImageSignature" => []}} ->
        {:error, :enoent}

      {:ok, %{"ImageSignature" => [sig | _]}} ->
        {:ok, sig}

      _ ->
        {:error, :failed}
    end
  end

  defp mount_image(ssl_sock, image_type, signature, extras) do
    command =
      %{
        "Command" => "MountImage",
        "ImageType" => image_type,
        "ImageSignature" => {:data, signature}
      }
      |> Map.merge(extras)

    Services.rpc(ssl_sock, command)
  end

  defp upload_image(ssl_sock, image_type, image, signature) do
    command = %{
      "Command" => "ReceiveBytes",
      "ImageType" => image_type,
      "ImageSize" => byte_size(image),
      "ImageSignature" => {:data, signature}
    }

    {:ok, %{"Status" => "ReceiveBytesAck"}} = Services.rpc(ssl_sock, command)
    :ok = :ssl.setopts(ssl_sock, packet: 0)
    :ok = :ssl.send(ssl_sock, image)
    :ok = :ssl.setopts(ssl_sock, packet: 4)
    {:ok, reply} = :ssl.recv(ssl_sock, 0)

    case Plist.decode(reply) do
      %{"Status" => "Complete"} ->
        :ok

      other ->
        {:error, other}
    end
  end

  defp get_manifest_from_tss(ssl_sock, build_manifest) do
    request = %{
      "@HostPlatformInfo" => "mac",
      "@UUID" => UUID.uuid4() |> String.upcase(),
      "@VersionInfo" => "libauthinstall-973.40.2"
    }

    {:ok, %{"PersonalizationIdentifiers" => persids}} =
      query_personalization_identifiers(ssl_sock)

    {:ok, %{"PersonalizationNonce" => nonce}} = query_personalization_nonce(ssl_sock)

    for {<<"Ap,", _::binary>> = k, v} <- persids, reduce: request do
      acc -> Map.put(acc, k, v)
    end

    board_id = persids["BoardId"]
    chip_id = persids["ChipID"]
    ecid = persids["UniqueChipID"]

    build_identity =
      Enum.find(build_manifest["BuildIdentities"], fn bid ->
        if board_id == bid["ApBoardID"] |> String.trim_leading("0x") |> String.to_integer(16) do
          chip_id == bid["ApChipID"] |> String.trim_leading("0x") |> String.to_integer(16)
        end
      end)

    manifest = build_identity["Manifest"]

    parameters = %{
      "ApProductionMode" => true,
      "ApSecurityDomain" => 1,
      "ApSecurityMode" => true,
      "ApSupportsImg4" => true
    }

    request =
      Map.merge(request, %{
        "@ApImg4Ticket" => true,
        "@BBTicket" => true,
        "ApBoardID" => board_id,
        "ApChipID" => chip_id,
        "ApECID" => ecid,
        "ApNonce" => {:data, nonce},
        "ApProductionMode" => true,
        "ApSecurityDomain" => 1,
        "ApSecurityMode" => true,
        "SepNonce" => {:data, <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>},
        "UID_MODE" => false
      })

    request =
      for {key, %{"Info" => _, "Trusted" => true} = value} <- manifest, reduce: request do
        acc ->
          rules = get_in(manifest, ["LoadableTrustCache", "Info", "RestoreRequestRules"]) || []

          tss_entry =
            value
            |> Map.delete("Info")
            |> Map.put_new("Digest", <<>>)
            |> Map.update!("Digest", fn data -> {:data, data} end)
            |> apply_request_restore_rules(parameters, rules)

          Map.put(acc, key, tss_entry)
      end

    body =
      [
        ~s(<?xml version="1.0" encoding="UTF-8"?>),
        ~s(<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">),
        ExMobileDevice.Plist.encode(request)
      ]
      |> IO.iodata_to_binary()

    hdrs = [
      {~c"Cache-Control", ~c"no-cache"},
      {~c"User-Agent", ~c"InetURL/1.0"},
      {~c"Expect", ~c""}
    ]

    url =
      Application.get_env(:exmobiledevice, :tss, @tss)
      |> String.to_charlist()

    content_type = ~c"text/xml; charset=\"utf-8\""

    httpc_opts = [
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]

    case :httpc.request(:post, {url, hdrs, content_type, body}, httpc_opts, body_format: :binary) do
      {:ok, {{_, 200, _}, _, <<"STATUS=0&MESSAGE=SUCCESS&REQUEST_STRING=", rest::binary>>}} ->
        {:ok, Plist.decode(rest)["ApImg4Ticket"]}
    end
  end

  defp apply_request_restore_rules(tss_entry, parameters, rules) do
    Enum.reduce(rules, tss_entry, fn rule, entry ->
      fulfilled =
        Enum.reduce_while(rule["Conditions"], true, fn {k, v}, _ ->
          v2 =
            case k do
              "ApRawProductionMode" -> parameters["ApProductionMode"]
              "ApCurrentProductionMode" -> parameters["ApProductionMode"]
              "ApRawSecurityMode" -> parameters["ApSecurityMode"]
              "ApRequiresImage4" -> parameters["ApSupportsImg4"]
              "ApDemotionPolicyOverride" -> parameters["DemotionPolicy"]
              "ApInRomDFU" -> parameters["ApInRomDFU"]
              _ -> nil
            end

          if v2 && v == v2 do
            {:cont, true}
          else
            {:halt, false}
          end
        end)

      if fulfilled do
        Enum.reduce(rule["Actions"], entry, fn
          {_, 255}, acc -> acc
          {k, v}, acc -> Map.put(acc, k, v)
        end)
      else
        entry
      end
    end)
  end

  defp query_personalization_nonce(ssl_sock) do
    command = %{
      "Command" => "QueryNonce",
      "PersonalizedImageType" => "DeveloperDiskImage"
    }

    Services.rpc(ssl_sock, command)
  end

  defp query_personalization_identifiers(ssl_sock) do
    command = %{
      "Command" => "QueryPersonalizationIdentifiers",
      "PersonalizedImageType" => "Personalized"
    }

    Services.rpc(ssl_sock, command)
  end

  defp query_personalization_manifest(ssl_sock, signature) do
    command = %{
      "Command" => "QueryPersonalizationManifest",
      "PersonalizedImageType" => "DeveloperDiskImage",
      "ImageType" => "DeveloperDiskImage",
      "ImageSignature" => {:data, signature}
    }

    Services.rpc(ssl_sock, command)
  end

  defp run_in_task(udid, request) when is_map(request) do
    run_in_task(fn ->
      with {:ok, ssl_sock} <- Services.connect(udid, @service) do
        Services.rpc(ssl_sock, request)
      end
    end)
  end

  defp run_in_task(fun) when is_function(fun, 0) do
    task = TaskSupervisor.async_nolink(fun)
    {:ok, result} = Task.yield(task, :infinity) || Task.shutdown(task)
    result
  end
end
