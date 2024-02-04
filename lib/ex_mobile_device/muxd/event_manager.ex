defmodule ExMobileDevice.Muxd.EventManager do
  # A gen_event process for forwarding muxd notifications
  @moduledoc false

  def child_spec(_args) do
    %{
      id: __MODULE__,
      start: {:gen_event, :start_link, [{:local, __MODULE__}, [hibernate_after: 60_000]]}
    }
  end

  defmodule Handler do
    # A gen_event handler that forwards muxd notications to a
    # subscriber process
    @moduledoc false
    @behaviour :gen_event

    @impl true
    def init(subscriber) do
      # Watch for subscriber exits
      ref = Process.monitor(subscriber)
      {:ok, {ref, subscriber}}
    end

    @impl true
    def handle_call(_, state) do
      {:ok, :ok, state}
    end

    @impl true
    def handle_event(event, {_, subscriber} = state) do
      send(subscriber, event)
      {:ok, state}
    end

    @impl true
    def handle_info({:DOWN, ref, :process, subscriber, _}, {ref, subscriber}) do
      # If the subscriber exits, remove this handler
      :remove_handler
    end

    def handle_info(_, state) do
      {:ok, state}
    end
  end

  def subscribe(pid \\ self()) do
    :gen_event.add_handler(__MODULE__, Handler, pid)
  end

  def notify(event) do
    :gen_event.notify(__MODULE__, event)
  end
end
