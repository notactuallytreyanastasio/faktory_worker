defmodule Experiment.LifeCheck do
  use GenServer

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  ## Callbacks
  @impl true
  def init(opts) do
    _beat_ref = Process.send_after(self(), :nowhere, 5_000)
    _beat_ref = Process.send_after(self(), :amialive, 10_000)
    {:ok, opts}
  end

  @impl true
  def handle_info(:amialive, state) do
    IO.puts("I AM ALIVE")
    FaktoryWorker.send_command({:fetch, []})
    {:noreply, state}
  end
  def handle_info(:nowhere, state) do
    IO.puts("I AM nowhere")
    FaktoryWorker.send_command({:fetch, []})
    {:noreply, state}
  end
end
defmodule Experiment.Supervisor do
  # Automatically defines child_spec/1
  use Supervisor
  require Logger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    opts = Keyword.put_new([], :name, FaktoryWorker)
    children = [
      {FaktoryWorker, [name: :faktory_test]},
      {FaktoryWorker.Pool, [
        name: FaktoryWorker,
        worker_pool: [
          size: 1,
          disable_fetch: false,
          queues: [
            ["default"]
          ]
        ]
      ]},
      {Experiment.LifeCheck, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def handle_info({:EXIT, _from, reason}, state) do
    Logger.info "!!!!!!!!!!!!!!!!!! exiting"
    {:stop, reason, state} # see GenServer docs for other return types
  end

  def handle_info({:EXIT, pid, {:timeout, {:gen_server, :call, [name, {:checkout, ref, _}, timeout]}}}) do
    require IEx; IEx.pry
  end

end

defmodule Experiment do
  defmodule MyWorker do
    use FaktoryWorker.Job

    def perform() do
      IO.puts("Doing some work")
      :timer.sleep(3_000)
    end
  end


  def start do
    children = [
      {Experiment.Supervisor, []}
    ]
    {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_all)
#    Process.unlink(pid)
    pid
  end

  def killit() do
    {:ok, pid} = Task.Supervisor.start_link()
    Enum.each(1..100, fn _n ->
      Task.Supervisor.async(pid, fn ->
        MyWorker.perform_async([])
        FaktoryWorker.send_command({:fetch, []})
      end)
    end)
  end
end
