defmodule FaktoryWorker.WorkerSupervisor do
  @moduledoc false

  # our supervisor that if we wanted to manage things we would enter here
  use Supervisor

  alias FaktoryWorker.Random

  @spec start_link(opts :: keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: :"#{name}_worker_supervisor")
  end

  @impl true
  def init(opts) do
    opts = Keyword.put(opts, :process_wid, Random.process_wid())

    # we probably start the producer/consumer here now
    children = [
      {FaktoryWorker.Worker.Pool, opts},
      {FaktoryWorker.Worker.HeartbeatServer, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
