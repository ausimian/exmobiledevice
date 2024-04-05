defmodule ExMobileDevice.WebInspector do
  @moduledoc """
  Functions for controlling Mobile Safari.

  This module provides a means of controlling Safari, without requiring SafariDriver.
  Starting an instance of this process will create a connection to an automated safari
  instance, on the specified device.

  ## Example
      iex(1)> alias ExMobileDevice.WebInspector
      ExMobileDevice.WebInspector
      iex(2)> {:ok, pid} = WebInspector.start_supervised("00008120-0018DEADC0DEFACE")
      {:ok, #PID<0.208.0>}
      iex(3)> {:ok, page} = WebInspector.create_page(pid)
      {:ok, "page-7102B011-5BC0-4785-87DF-ADBA671EAD74"}
      iex(4)> WebInspector.navigate_to(pid, page, "https://elixir-lang.org")
      :ok
  """
  use GenStateMachine, restart: :temporary
  use TypedStruct

  require Logger

  @doc """
  Create a supervised connection to the 'webinspector' service on the device.

  The connection is supervised by an internal supervision tree of `exmobiledevice`.
  To manually stop the connection, call `stop/1`.

  > #### Controlling Process {: .info}
  >
  > On success, the caller is the 'controlling process' of the connection. Should
  > the caller exit for any reason, the connection will also exit, which will
  > in turn tear down the automation pages.
  >
  > To transfer control to another process, call `set_controlling_process/2`.
  """
  @spec start_supervised(String.t()) :: DynamicSupervisor.on_start_child()
  def start_supervised(udid) when is_binary(udid) do
    args = [udid: udid, controlling_process: self()]
    DynamicSupervisor.start_child(ExMobileDevice.WebInspector.Supervisor, {__MODULE__, args})
  end

  @doc """
  Stop the webinspector process.

  Stopping the process will terminate the connection to the webinspector service
  on the device, which will remove any automation pages from Safari.
  """
  @spec stop(pid) :: :ok
  def stop(pid) do
    GenStateMachine.stop(pid)
  end

  @doc """
  Transfer ownership to the specified process.

  Transfers controlling ownership of `pid` to `cp`. The caller must be the
  current owner.
  """
  @spec set_controlling_process(:gen_statem.server_ref(), pid()) :: :ok | {:error, any()}
  def set_controlling_process(pid, cp) when is_pid(cp) do
    GenStateMachine.call(pid, {:set_cp, cp})
  end

  @doc """
  Wait for the session to be created.
  """
  @spec wait_for_session(pid, non_neg_integer() | :infinity) :: :ok | {:error, :failed | :timeout}
  def wait_for_session(pid, timeout \\ 5000) do
    deadline =
      if timeout == :infinity do
        timeout
      else
        :erlang.monotonic_time(:millisecond) + timeout
      end

    GenStateMachine.call(pid, {:wait_for_session, deadline})
  end

  @doc """
  Create a new automation page.
  """
  @spec create_page(:gen_statem.server_ref()) :: {:ok, String.t()} | {:error, any()}
  def create_page(pid) do
    GenStateMachine.call(pid, :create_page)
  end

  @doc """
  List the current automation pages.
  """
  @spec list_pages(:gen_statem.server_ref()) :: {:ok, list(map())} | {:error, any()}
  def list_pages(pid) do
    GenStateMachine.call(pid, :list_pages)
  end

  @doc """
  Switch to the specified page.
  """
  @spec switch_to_page(:gen_statem.server_ref(), String.t()) :: :ok | {:error, any()}
  def switch_to_page(pid, page) do
    GenStateMachine.call(pid, {:switch_to_page, page})
  end

  @doc """
  Navigate the specified page to the provided url.

  Supported options are:

  - `timeout`: The page-load timeout in milliseconds. Defaults to 30_000 (30 seconds)
  """
  @spec navigate_to(:gen_statem.server_ref(), String.t(), String.t(), Keyword.t()) ::
          :ok | {:error, any()}
  def navigate_to(pid, page, url, opts \\ []) do
    GenStateMachine.call(pid, {:navigate_to, page, url, opts})
  end

  @doc """
  Go to the previous url in the page's history.
  """
  @spec go_back(:gen_statem.server_ref(), String.t()) :: :ok | {:error, any()}
  def go_back(pid, page) do
    GenStateMachine.call(pid, {:go_back, page})
  end

  @doc """
  Go to the next url in the page's history.
  """
  @spec go_forward(:gen_statem.server_ref(), String.t()) :: :ok | {:error, any()}
  def go_forward(pid, page) do
    GenStateMachine.call(pid, {:go_forward, page})
  end

  @doc """
  Reload the page's current url.
  """
  @spec reload(:gen_statem.server_ref(), String.t()) :: :ok | {:error, any()}
  def reload(pid, page) do
    GenStateMachine.call(pid, {:reload, page})
  end

  @doc """
  Take a screenshot of the current page, returning the bytes in PNG format.
  """
  @spec take_screenshot(:gen_statem.server_ref(), String.t()) :: {:ok, binary()} | {:error, any()}
  def take_screenshot(pid, page) do
    GenStateMachine.call(pid, {:take_screenshot, page})
  end

  @doc """
  Close the specified page.
  """
  @spec close_page(:gen_statem.server_ref(), String.t()) :: :ok | {:error, any()}
  def close_page(pid, page) do
    GenStateMachine.call(pid, {:close_page, page})
  end

  @doc false
  def start_link(args) do
    GenStateMachine.start_link(__MODULE__, args, hibernate_after: 15_000)
  end

  @service "com.apple.webinspector"
  @bundle "com.apple.mobilesafari"
  @selector "__selector"
  @argument "__argument"

  @rpcReportIdentifier "_rpc_reportIdentifier:"
  @rpcReportCurrentState "_rpc_reportCurrentState:"
  @rpcReportConnectedApplications "_rpc_reportConnectedApplicationList:"
  @rpcApplicationConnected "_rpc_applicationConnected:"
  @rpcApplicationUpdated "_rpc_applicationUpdated:"
  @rpcApplicationDisconnected "_rpc_applicationDisconnected:"
  @rpcApplicationSentListing "_rpc_applicationSentListing:"
  @rpcApplicationSentData "_rpc_applicationSentData:"
  @rpcRequestApplicationLaunch "_rpc_requestApplicationLaunch:"
  @rpcForwardAutomationSessionRequest "_rpc_forwardAutomationSessionRequest:"
  @rpcForwardSocketSetup "_rpc_forwardSocketSetup:"
  @rpcForwardSocketData "_rpc_forwardSocketData:"

  @wirConnectionIdentifierKey "WIRConnectionIdentifierKey"
  @wirAutomationAvailabilityKey "WIRAutomationAvailabilityKey"
  @wirAutomationAvailable "WIRAutomationAvailabilityAvailable"
  @wirApplicationDictionaryKey "WIRApplicationDictionaryKey"
  @wirApplicationIdentifierKey "WIRApplicationIdentifierKey"
  @wirApplicationBundleIdentifierKey "WIRApplicationBundleIdentifierKey"
  @wirIsApplicationReadyKey "WIRIsApplicationReadyKey"
  @wirSessionIdentifierKey "WIRSessionIdentifierKey"
  @wirSessionCapabilitiesKey "WIRSessionCapabilitiesKey"
  @wirListingKey "WIRListingKey"
  @wirTypeKey "WIRTypeKey"
  @wirTypeAutomation "WIRTypeAutomation"
  @wirPageIdentifierKey "WIRPageIdentifierKey"
  @wirSenderKey "WIRSenderKey"
  @wirSocketDataKey "WIRSocketDataKey"
  @wirDestinationKey "WIRDestinationKey"
  @wirMessageDataKey "WIRMessageDataKey"

  typedstruct do
    @typedoc false
    # The socket connected to the web-inspector service
    field(:ssl_sock, :ssl.sslsocket())
    # The unique session id identifying this connection
    field(:session_id, String.t())
    # The pid of the controlling process
    field(:cp_pid, reference())
    # The monitor reference to the controlling process
    field(:cp_mref, reference())
    # The reported state of the safari process, if any
    field(:safari, %{String.t() => any} | nil)
    # The id of the currently 'automatable' page.
    field(:page_id, String.t() | nil)
    # The sequence number of the next request to the page
    field(:page_out, non_neg_integer(), default: 0)
    # A map of pending replies to page requests. The key is the
    # sequence number and the value is an arbitrary context.
    field(:page_in, %{non_neg_integer() => any()}, default: %{})
  end

  @impl true
  def init(args) do
    proc = Keyword.fetch!(args, :controlling_process)
    udid = Keyword.fetch!(args, :udid)

    with {:ok, ssl_sock} <- ExMobileDevice.Services.connect(udid, @service) do
      session_id = UUID.uuid4() |> String.upcase()

      if automation_enabled?(ssl_sock, session_id) do
        :ok = :ssl.setopts(ssl_sock, active: :once)
        mref = Process.monitor(proc)

        timeout = Keyword.get(args, :timeout, 30_000)

        next_events = [
          {{:timeout, :start_session}, timeout, nil},
          {:next_event, :internal, :start_session}
        ]

        {:ok, :created,
         %__MODULE__{ssl_sock: ssl_sock, session_id: session_id, cp_pid: proc, cp_mref: mref},
         next_events}
      else
        {:stop, :no_automation}
      end
    end
  end

  @impl true

  #
  # Handle api calls
  #
  def handle_event({:call, {caller, _} = from}, {:set_cp, cp}, _, %__MODULE__{} = data) do
    if caller == data.cp_pid do
      # The controlling process can transfer control to another process
      mref = Process.monitor(cp)
      Process.demonitor(data.cp_mref, [:flush])
      {:keep_state, %__MODULE__{data | cp_pid: cp, cp_mref: mref}, {:reply, from, :ok}}
    else
      {:keep_state_and_data, {:reply, from, {:error, :not_controlling_process}}}
    end
  end

  def handle_event({:call, from}, _, :failed, %__MODULE__{}) do
    # If the process failed to initialize, all requests will fail
    {:keep_state_and_data, {:reply, from, {:error, :failed}}}
  end

  def handle_event({:call, _}, _, state, %__MODULE__{}) when state != :connected do
    # All requests must otherwise wait for the process to connect to safari
    {:keep_state_and_data, :postpone}
  end

  def handle_event({:call, from}, :create_page, _, %__MODULE__{} = data) do
    send_rpc("createBrowsingContext", [], from, data, fn
      %{"result" => %{"handle" => handle}}, data ->
        {:keep_state, data, {:reply, from, {:ok, handle}}}

      %{"error" => error}, data ->
        {:keep_state, data, {:reply, from, {:error, error}}}
    end)
  end

  def handle_event({:call, from}, :list_pages, _, %__MODULE__{} = data) do
    send_rpc("getBrowsingContexts", [], from, data, fn
      %{"result" => %{"contexts" => contexts}}, data ->
        pages =
          for %{"active" => active, "handle" => handle, "url" => url} <- contexts do
            %{active: active, id: handle, url: url}
          end

        {:keep_state, data, {:reply, from, {:ok, pages}}}

      %{"error" => error}, data ->
        {:keep_state, data, {:reply, from, {:error, error}}}
    end)
  end

  def handle_event({:call, from}, {:navigate_to, page, url, opts}, _, %__MODULE__{} = data) do
    args = [handle: page, url: url] ++ page_load_timeout(opts)

    send_rpc("navigateBrowsingContext", args, from, data, fn
      %{"result" => %{}}, data ->
        {:keep_state, data, {:reply, from, :ok}}

      %{"error" => error}, data ->
        {:keep_state, data, {:reply, from, {:error, error}}}
    end)
  end

  def handle_event({:call, from}, {:switch_to_page, page}, _, %__MODULE__{} = data) do
    args = [browsingContextHandle: page, frameHandle: ""]

    send_rpc("switchToBrowsingContext", args, from, data, fn
      %{"result" => %{}}, data ->
        {:keep_state, data, {:reply, from, :ok}}

      %{"error" => error}, data ->
        {:keep_state, data, {:reply, from, {:error, error}}}
    end)
  end

  def handle_event({:call, from}, {:take_screenshot, page}, _, %__MODULE__{} = data) do
    args = [handle: page, scrollIntoViewIfNeeded: true, clipToViewport: true]

    send_rpc("takeScreenshot", args, from, data, fn
      %{"result" => %{"data" => base64}}, data ->
        {:keep_state, data, {:reply, from, {:ok, Base.decode64!(base64)}}}

      %{"error" => error}, data ->
        {:keep_state, data, {:reply, from, {:error, error}}}
    end)
  end

  def handle_event({:call, from}, {:go_forward, page}, _, %__MODULE__{} = data) do
    send_rpc("goForwardInBrowsingContext", [handle: page], from, data, fn
      %{"result" => %{}}, data ->
        {:keep_state, data, {:reply, from, :ok}}

      %{"error" => error}, data ->
        {:keep_state, data, {:reply, from, {:error, error}}}
    end)
  end

  def handle_event({:call, from}, {:go_back, page}, _, %__MODULE__{} = data) do
    send_rpc("goBackInBrowsingContext", [handle: page], from, data, fn
      %{"result" => %{}}, data ->
        {:keep_state, data, {:reply, from, :ok}}

      %{"error" => error}, data ->
        {:keep_state, data, {:reply, from, {:error, error}}}
    end)
  end

  def handle_event({:call, from}, {:reload, page}, _, %__MODULE__{} = data) do
    send_rpc("reloadBrowsingContext", [handle: page], from, data, fn
      %{"result" => %{}}, data ->
        {:keep_state, data, {:reply, from, :ok}}

      %{"error" => error}, data ->
        {:keep_state, data, {:reply, from, {:error, error}}}
    end)
  end

  def handle_event({:call, from}, {:close_page, page}, _, %__MODULE__{} = data) do
    send_rpc("closeBrowsingContext", [handle: page], from, data, fn
      %{"result" => %{}}, data ->
        {:keep_state, data, {:reply, from, :ok}}

      %{"error" => error}, data ->
        {:keep_state, data, {:reply, from, {:error, error}}}
    end)
  end

  def handle_event({:call, from}, {:wait_for_session, _}, :connected, _) do
    {:keep_state_and_data, {:reply, from, :ok}}
  end

  def handle_event({:call, from}, {:wait_for_session, _}, :failed, _) do
    {:keep_state_and_data, {:reply, from, {:error, :failed}}}
  end

  def handle_event({:call, _from}, {:wait_for_session, :infinity}, _, _) do
    {:keep_state_and_data, :postpone}
  end

  def handle_event({:call, from}, {:wait_for_session, deadline}, _, _) do
    next_events = [
      :postpone,
      {{:timeout, {:wait_for_session, from}}, deadline, nil, [abs: true]}
    ]

    {:keep_state_and_data, next_events}
  end

  #
  # Event handling
  #
  def handle_event(:internal, :start_session, state, %__MODULE__{} = data) do
    case state do
      :created ->
        {:keep_state_and_data, :postpone}

      :initialized ->
        if get_in(data.safari, [@wirAutomationAvailabilityKey]) == @wirAutomationAvailable do
          {:next_state, :ready, data, :postpone}
        else
          # Start safari if it is not already started
          bundle_key = %{@wirApplicationBundleIdentifierKey => @bundle}

          case send_msg(data.ssl_sock, data.session_id, @rpcRequestApplicationLaunch, bundle_key) do
            :ok ->
              {:keep_state_and_data, :postpone}

            _error ->
              {:next_state, :failed, data}
          end
        end

      :ready ->
        next_event = [{:next_event, :internal, :start_automation_session}]
        {:keep_state_and_data, next_event}
    end
  end

  def handle_event(:internal, :start_automation_session, _, %__MODULE__{} = data) do
    if data.safari[@wirAutomationAvailabilityKey] == @wirAutomationAvailable do
      params = %{
        @wirSessionIdentifierKey => data.session_id,
        @wirApplicationIdentifierKey => data.safari[@wirApplicationIdentifierKey],
        @wirSessionCapabilitiesKey => %{
          "org.webkit.webdriver.webrtc.allow-insecure-media-capture" => true,
          "org.webkit.webdriver.webrtc.suppress-ice-candidate-filtering" => false
        }
      }

      case send_msg(data.ssl_sock, data.session_id, @rpcForwardAutomationSessionRequest, params) do
        :ok ->
          :keep_state_and_data

        _error ->
          {:next_state, :failed, data}
      end
    else
      {:next_state, :failed, data}
    end
  end

  def handle_event(:internal, {:recv, msg}, state, %__MODULE__{} = data) do
    args = msg[@argument]

    case msg[@selector] do
      @rpcReportConnectedApplications when state == :created ->
        update = find_safari(Map.values(args[@wirApplicationDictionaryKey]))
        {:next_state, :initialized, %__MODULE__{data | safari: update}}

      @rpcApplicationSentData ->
        if args[@wirDestinationKey] == data.session_id do
          case Jason.decode!(args[@wirMessageDataKey]) do
            %{"id" => id} = response ->
              case Map.pop(data.page_in, id) do
                {nil, _} ->
                  :keep_state_and_data

                {fun, pending} ->
                  fun.(response, %__MODULE__{data | page_in: pending})
              end

            _ ->
              :keep_state_and_data
          end
        else
          :keep_state_and_data
        end

      @rpcApplicationSentListing ->
        app_id = get_in(data.safari, [@wirApplicationIdentifierKey])

        if app_id == args[@wirApplicationIdentifierKey] do
          find_automation_page(args[@wirListingKey], data)
        else
          :keep_state_and_data
        end

      @rpcApplicationDisconnected ->
        app_id = get_in(data.safari, [@wirApplicationIdentifierKey])

        if app_id == args[@wirApplicationIdentifierKey] do
          {:keep_state, %__MODULE__{data | safari: nil, page_id: nil}}
        else
          :keep_state_and_data
        end

      rpc when rpc in [@rpcApplicationConnected, @rpcApplicationUpdated] ->
        if args[@wirApplicationBundleIdentifierKey] == @bundle do
          if state == :initialized && safari_automated?(args) && safari_ready?(args) do
            {:next_state, :ready, %__MODULE__{data | safari: args}}
          else
            {:keep_state, %__MODULE__{data | safari: args}}
          end
        else
          :keep_state_and_data
        end

      _ ->
        :keep_state_and_data
    end
  end

  def handle_event(:internal, :connect_page, _, %__MODULE__{} = data) do
    params = %{
      @wirSenderKey => data.session_id,
      @wirApplicationIdentifierKey => data.safari[@wirApplicationIdentifierKey],
      @wirPageIdentifierKey => data.page_id
    }

    case send_msg(data.ssl_sock, data.session_id, @rpcForwardSocketSetup, params) do
      :ok -> :keep_state_and_data
    end
  end

  #
  # Socket handling
  #

  def handle_event(:info, {:ssl, socket, data}, _, %__MODULE__{ssl_sock: socket}) do
    :ok = :ssl.setopts(socket, active: :once)
    {:keep_state_and_data, {:next_event, :internal, {:recv, ExMobileDevice.Plist.decode(data)}}}
  end

  def handle_event(:info, {:ssl_closed, socket}, _, %__MODULE__{ssl_sock: socket}) do
    {:stop, :shutdown}
  end

  def handle_event(:info, {:DOWN, ref, :process, _, _}, _, %__MODULE__{cp_mref: ref}) do
    {:stop, :shutdown}
  end

  def handle_event({:timeout, {:wait_for_session, from}}, _, _, _) do
    {:keep_state_and_data, {:reply, from, {:error, :timeout}}}
  end

  #
  # Session creation timeout
  #

  def handle_event({:timeout, :start_session}, _, _, %__MODULE__{} = data) do
    {:next_state, :failed, data}
  end

  defp find_safari(applications) do
    Enum.find(applications, &match?(%{@wirApplicationBundleIdentifierKey => @bundle}, &1))
  end

  defp safari_automated?(%{@wirAutomationAvailabilityKey => @wirAutomationAvailable}), do: true
  defp safari_automated?(_), do: false

  defp safari_ready?(safari), do: safari[@wirIsApplicationReadyKey]

  defp send_rpc(method, args, from, data, fun) do
    seqno = data.page_out

    case send_cmd(data, seqno, method, args) do
      :ok ->
        page_in = Map.put(data.page_in, seqno, fun)
        {:keep_state, %__MODULE__{data | page_out: seqno + 1, page_in: page_in}}

      error ->
        stop_and_reply(error, from)
    end
  end

  defp send_cmd(%__MODULE__{} = data, id, method, args) do
    call_args = %{
      "method" => "Automation.#{method}",
      "params" => Map.new(args),
      "id" => id
    }

    call_params = %{
      @wirApplicationIdentifierKey => data.safari[@wirApplicationIdentifierKey],
      @wirPageIdentifierKey => data.page_id,
      @wirSessionIdentifierKey => data.session_id,
      @wirSocketDataKey => {:data, Jason.encode!(call_args)}
    }

    send_msg(data.ssl_sock, data.session_id, @rpcForwardSocketData, call_params)
  end

  defp find_automation_page(pages, %__MODULE__{session_id: sid} = data) do
    candidates =
      for {_, %{@wirTypeKey => @wirTypeAutomation, @wirSessionIdentifierKey => ^sid} = page} <-
            pages do
        page[@wirPageIdentifierKey]
      end

    if pid = List.first(candidates) do
      cond do
        is_nil(data.page_id) ->
          {:keep_state, %__MODULE__{data | page_id: pid}, {:next_event, :internal, :connect_page}}

        get_in(pages, [to_string(data.page_id), @wirConnectionIdentifierKey]) == sid ->
          {:next_state, :connected, data, {{:timeout, :start_session}, :cancel}}
      end
    else
      :keep_state_and_data
    end
  end

  defp page_load_timeout(opts) do
    if t = Keyword.get(opts, :timeout) do
      [pageLoadTimeout: t]
    else
      []
    end
  end

  defp automation_enabled?(ssl_sock, session_id) do
    with :ok <- send_msg(ssl_sock, session_id, @rpcReportIdentifier),
         {:ok, %{@selector => @rpcReportCurrentState} = reply} <- recv_msg(ssl_sock, 5000) do
      get_in(reply, [@argument, @wirAutomationAvailabilityKey]) == @wirAutomationAvailable
    else
      _ -> false
    end
  end

  defp recv_msg(ssl_sock, timeout) do
    with {:ok, packet} <- :ssl.recv(ssl_sock, 0, timeout) do
      {:ok, ExMobileDevice.Plist.decode(packet)}
    end
  end

  defp send_msg(ssl_sock, conn_id, selector, args \\ %{}) do
    send_plist(ssl_sock, %{
      @selector => selector,
      @argument => Map.put(args, @wirConnectionIdentifierKey, conn_id)
    })
  end

  defp stop_and_reply(error, to) do
    if to do
      {:stop_and_reply, {:shutdown, error}, {:reply, to, error}}
    else
      {:stop, {:shutdown, error}}
    end
  end

  defp send_plist(ssl_sock, plist) do
    :ssl.send(ssl_sock, ExMobileDevice.Plist.encode(plist))
  end
end
