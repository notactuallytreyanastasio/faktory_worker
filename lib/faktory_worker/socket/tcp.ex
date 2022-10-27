# we send payloads here, this will be the consumer
defmodule FaktoryWorker.Socket.Tcp do
  @moduledoc false

  # is this our ideal consumer? not sure

  alias FaktoryWorker.Connection

  @behaviour FaktoryWorker.Socket

  @impl true
  def connect(host, port, _opts \\ []) do
    # IO.puts("tcp.ex: Connecting\n")
    with {:ok, socket} <- try_connect(host, port) do
      {:ok, %Connection{host: host, port: port, socket: socket, socket_handler: __MODULE__}}
    end
  end

  @impl true
  def send(%{socket: socket}, payload) do
    # IO.puts("tcp.ex: sending message on socket #{inspect(socket)} with payload: #{inspect(payload)}\n")
    :gen_tcp.send(socket, payload)
  end

  @impl true
  def recv(%{socket: socket}) do
    # IO.puts(" tcp.ex: recv on socket #{inspect(socket)}\n")
    :gen_tcp.recv(socket, 0)
  end

  @impl true
  def recv(%{socket: socket}, length) do
    # IO.puts("tcp.ex: recv on socket #{inspect(socket)} with length #{inspect(length)}\n")
    set_packet_mode(socket, :raw)
    result = :gen_tcp.recv(socket, length)
    set_packet_mode(socket, :line)

    result
  end

  defp try_connect(host, port) do
    host = String.to_charlist(host)

    :gen_tcp.connect(host, port, [:binary, active: false, packet: :line])
  end

  defp set_packet_mode(socket, mode), do: :inet.setopts(socket, packet: mode)
end

# defmodule RateLimiter do
#   use GenStage

#   def init(_) do
#     # Our state will keep all producers and their pending demand
#     {:consumer, %{}}
#   end

#   def handle_subscribe(:producer, opts, from, producers) do
#     # We will only allow max_demand events every 5000 milliseconds
#     pending = opts[:max_demand] || 1000
#     interval = opts[:interval] || 5000

#     # Register the producer in the state
#     producers = Map.put(producers, from, {pending, interval})
#     # Ask for the pending events and schedule the next time around
#     producers = ask_and_schedule(producers, from)

#     # Returns manual as we want control over the demand
#     {:manual, producers}
#   end

#   def handle_cancel(_, from, producers) do
#     # Remove the producers from the map on unsubscribe
#     {:noreply, [], Map.delete(producers, from)}
#   end

#   def handle_events(events, from, producers) do
#     # Bump the amount of pending events for the given producer
#     producers = Map.update!(producers, from, fn {pending, interval} ->
#       {pending + length(events), interval}
#     end)

#     # Consume the events by printing them.
    # IO.puts(events)

#     # A producer_consumer would return the processed events here.
#     {:noreply, [], producers}
#   end

#   def handle_info({:ask, from}, producers) do
#     # This callback is invoked by the Process.send_after/3 message below.
#     {:noreply, [], ask_and_schedule(producers, from)}
#   end

#   defp ask_and_schedule(producers, from) do
#     case producers do
#       %{^from => {pending, interval}} ->
#         # Ask for any pending events
#         GenStage.ask(from, pending)
#         # And let's check again after interval
#         Process.send_after(self(), {:ask, from}, interval)
#         # Finally, reset pending events to 0
#         Map.put(producers, from, {0, interval})
#       %{} ->
#         producers
#     end
#   end
# end
