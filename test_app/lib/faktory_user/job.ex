defmodule FaktoryUser.MyJob do
  use FaktoryWorker.Job

  def perform do
    IO.puts("doing work")
    :timer.sleep(500)
    :ok
  end
end
