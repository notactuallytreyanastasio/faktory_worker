defmodule FaktoryWorker.Pool do
  @moduledoc false

  def child_spec(opts) do
    name = opts[:name]
    pool_name = format_pool_name(name)
    pool_config = Keyword.get(opts, :pool, [])

    :poolboy.child_spec(
      pool_name,
      [
        {:name, {:local, pool_name}},
        {:worker_module, FaktoryWorker.ConnectionManager.Server},
        {:size, 1},
        {:max_overflow, 0}
      ],
      Keyword.get(opts, :connection, [])
    )
  end

  def handle_info({:EXIT, pid, {:timeout, {:gen_server, :call, [name, {:checkout, ref, _}, timeout]}}}) do
    require IEx; IEx.pry
  end

  @spec format_pool_name(name :: atom()) :: atom()
  def format_pool_name(name) when is_atom(name) do
    :"#{name}_pool"
  end
end
