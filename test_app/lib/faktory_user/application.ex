defmodule FaktoryUser.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    faktory_worker_opts = Application.get_env(:faktory_user, FaktoryWorker)
    children = [
      {FaktoryWorker, faktory_worker_opts}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FaktoryUser.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
