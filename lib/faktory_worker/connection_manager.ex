defmodule ConnectionManagerEventProducer do
  use GenStage

  def start_link(number) do
    GenStage.start_link(A, number)
  end

  def init(counter) do
    {:producer, counter}
  end

  def handle_demand(demand, counter) when demand > 0 do
    # If the counter is 3 and we ask for 2 items, we will
    # emit the items 3 and 4, and set the state to 5.
    events = Enum.to_list(counter..counter+demand-1)
    {:noreply, events, counter + demand}
  end
end

defmodule RateLimiter do
  use GenStage

  def init(_) do
    # Our state will keep all producers and their pending demand
    {:consumer, %{}}
  end

  def handle_subscribe(:producer, opts, from, producers) do
    # We will only allow max_demand events every 5000 milliseconds
    pending = opts[:max_demand] || 1000
    interval = opts[:interval] || 5000

    # Register the producer in the state
    producers = Map.put(producers, from, {pending, interval})
    # Ask for the pending events and schedule the next time around
    producers = ask_and_schedule(producers, from)

    # Returns manual as we want control over the demand
    {:manual, producers}
  end

  def handle_cancel(_, from, producers) do
    # Remove the producers from the map on unsubscribe
    {:noreply, [], Map.delete(producers, from)}
  end

  def handle_events(events, from, producers) do
    # Bump the amount of pending events for the given producer
    producers = Map.update!(producers, from, fn {pending, interval} ->
      {pending + length(events), interval}
    end)

    # Consume the events by printing them.
    # this is where we would wire in the actual sending of the commands
    # given in here to be sent to faktory
    IO.inspect(events)

    # A producer_consumer would return the processed events here.
    {:noreply, [], producers}
  end

  def handle_info({:ask, from}, producers) do
    # This callback is invoked by the Process.send_after/3 message below.
    {:noreply, [], ask_and_schedule(producers, from)}
  end

  defp ask_and_schedule(producers, from) do
    case producers do
      %{^from => {pending, interval}} ->
        # Ask for any pending events
        GenStage.ask(from, pending)
        # And let's check again after interval
        Process.send_after(self(), {:ask, from}, interval)
        # Finally, reset pending events to 0
        Map.put(producers, from, {0, interval})
      %{} ->
        producers
    end
  end
end

{:ok, producer} = GenStage.start_link(ConnectionManagerEventProducer, [])
{:ok, consumer} = GenStage.start_link(FaktoryConnectionRateLimiter, :ok)

# Ask for 10 items every 2 seconds
GenStage.sync_subscribe(consumer, to: producer, max_demand: 10, interval: 2000)

defmodule FaktoryWorker.ConnectionManager do
  @moduledoc false

  alias FaktoryWorker.Connection
  alias FaktoryWorker.ConnectionManager

  require Logger

  @type t :: %__MODULE__{}

  @connection_errors [
    :closed,
    :enotconn,
    :econnrefused
  ]

  defstruct [:opts, :conn]

  @spec new(opts :: keyword()) :: ConnectionManager.t()
  def new(opts) do
    %__MODULE__{
      conn: open_connection(opts),
      opts: opts
    }
  end

  @spec send_command(
          state :: ConnectionManager.t(),
          command :: FaktoryWorker.Protocol.protocol_command(),
          allow_retry :: boolean()
        ) ::
          {Connection.response(), ConnectionManager.t()}
  def send_command(state, command, allow_retry \\ true) do

    case try_send_command(state, command) do
      {{:error, reason}, _} when reason in @connection_errors ->
        # IO.puts("connection_manager.ex: error: reason: #{reason}\n")
        error = {:error, "Failed to connect to Faktory"}
        state = %{state | conn: nil}

        if allow_retry,
          do: send_command(%{state | conn: nil}, command, false),
          else: {error, state}

      # Handle errors from Faktory that should not be tried again
      {{:error, "Halt: " <> reason = error}, state} ->
        # IO.puts("connection_manager.ex: error: halted\n")
        log_error(error, command)

        {{:ok, reason}, state}

      {{:ok, :closed}, state} ->
        # IO.puts("connection_manager.ex: connection closed\n")
        {{:ok, :closed}, %{state | conn: nil}}

      result ->
        # IO.puts("connection_manager.ex: Got result #{inspect(result)}\n")
        result
    end
  end

  defp try_send_command(%{conn: nil, opts: opts} = state, command) do
    case open_connection(opts) do
      nil ->
        {{:error, "Failed to connect to Faktory"}, state}

      connection ->
        state = %{state | conn: connection}

        try_send_command(state, command)
    end
  end

  defp try_send_command(%{conn: connection} = state, command) do
    result = Connection.send_command(connection, command)
    {result, state}
  end

  defp open_connection(opts) do
    case Connection.open(opts) do
      {:ok, connection} -> connection
      {:error, _reason} -> nil
    end
  end

  defp log_error(reason, {_, %{jid: jid}}) do
    Logger.warn("[#{jid}] #{reason}")
  end
end
