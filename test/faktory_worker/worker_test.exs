defmodule FaktoryWorker.WorkerTest do
  use ExUnit.Case

  import Mox
  import FaktoryWorker.ConnectionHelpers
  import ExUnit.CaptureLog

  alias FaktoryWorker.Worker
  alias FaktoryWorker.Random

  setup :set_mox_global
  setup :verify_on_exit!

  describe "new/2" do
    test "should return a worker struct" do
      process_wid = Random.process_wid()
      opts = [process_wid: process_wid, queues: ["test_queue", "test_queue_two"]]

      worker = Worker.new(opts)

      assert worker.process_wid == process_wid
      assert worker.worker_state == :ok
      assert worker.queues == ["test_queue", "test_queue_two"]
      assert worker.job_ref == nil
      assert worker.job_id == nil
      assert worker.job_timeout_ref == nil
    end

    test "should raise if no worker id is provided" do
      assert_raise KeyError, "key :process_wid not found in: []", fn ->
        Worker.new([])
      end
    end

    test "should raise if no queues is provided" do
      opts = [process_wid: Random.process_wid()]

      assert_raise KeyError, "key :queues not found in: #{inspect(opts)}", fn ->
        Worker.new(opts)
      end
    end

    test "should open a new worker connection" do
      worker_connection_mox()

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      worker = Worker.new(opts)

      assert is_pid(worker.conn_pid)
    end

    test "should schedule a fetch to be triggered" do
      opts = [process_wid: Random.process_wid(), queues: ["test_queue"]]

      Worker.new(opts)

      assert_receive :fetch
    end
  end

  describe "send_end/1" do
    @tag skip: true
    test "should send the 'END' command to faktory" do
      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, "END\r\n" ->
        :ok
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      result =
        opts
        |> Worker.new()
        |> Worker.send_end()

      assert result.conn_pid == nil
      assert result.worker_state == :ended
    end

    @tag skip: true
    test "should not send 'END' command when no connection has been setup" do
      assert Worker.send_end(%{}) == %{}
    end

    @tag skip: true
    test "should not send 'END' if the connection is no longer available" do
      worker_connection_mox()

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      worker = Worker.new(opts)

      Process.unlink(worker.conn_pid)
      Process.exit(worker.conn_pid, :shutdown)

      result = Worker.send_end(worker)

      assert result.conn_pid == nil
      assert result.worker_state == :ended
    end
  end

  # todo: more tests for multi queue fetching
  describe "send_fetch/1" do
    test "should send a fetch command and schedule next fetch when state is ':ok'" do
      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, "FETCH test_queue\r\n" ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:ok, "$-1\r\n"}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      opts
      |> Worker.new()
      |> Worker.send_fetch()

      consume_initial_fetch_message()

      assert_receive :fetch
    end

    test "should not send a fetch command and schedule next fetch when state is ':quiet'" do
      worker_connection_mox()

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      opts
      |> Worker.new()
      |> Map.put(:worker_state, :quiet)
      |> Worker.send_fetch()

      consume_initial_fetch_message()

      refute_received :fetch
    end

    test "should not send a fetch command and schedule next fetch when state is ':terminate'" do
      worker_connection_mox()

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      opts
      |> Worker.new()
      |> Map.put(:worker_state, :terminate)
      |> Worker.send_fetch()

      consume_initial_fetch_message()

      refute_received :fetch
    end

    test "should not send a fetch command and schedule next fetch when state is ':running_job'" do
      worker_connection_mox()

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      opts
      |> Worker.new()
      |> Map.put(:worker_state, :running_job)
      |> Worker.send_fetch()

      consume_initial_fetch_message()

      refute_received :fetch
    end

    test "should send a fetch command without a queue configured" do
      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, "FETCH default\r\n" ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:ok, "$-1\r\n"}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["default"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      opts
      |> Worker.new()
      |> Worker.send_fetch()
    end

    test "should leave the worker state set to ':ok' when there is no job to process" do
      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, "FETCH test_queue\r\n" ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:ok, "$-1\r\n"}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      result =
        opts
        |> Worker.new()
        |> Worker.send_fetch()

      assert result.worker_state == :ok
    end

    test "should log error and schedule next fetch when worker cannot connect" do
      expect(FaktoryWorker.SocketMock, :connect, fn _host, _port, _opts ->
        {:error, :econnrefused}
      end)

      expect(FaktoryWorker.SocketMock, :connect, fn _host, _port, _opts ->
        {:error, :econnrefused}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        retry_interval: 1,
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      worker = Worker.new(opts)

      log_message = capture_log(fn -> Worker.send_fetch(worker) end)

      consume_initial_fetch_message()

      assert log_message =~
               "[faktory-worker] Failed to fetch job due to 'Failed to connect to Faktory' wid-#{
                 worker.process_wid
               }"

      assert_receive :fetch
    end

    test "should log error, sleep, and then successfully fetch next time" do
      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, "FETCH test_queue\r\n" ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:ok, "-SHUTDOWN Shutdown in progress\r\n"}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        retry_interval: 1,
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      worker = Worker.new(opts)

      log_message = capture_log(fn -> Worker.send_fetch(worker) end)

      consume_initial_fetch_message()

      assert log_message =~
               "[faktory-worker] Failed to fetch job due to 'Shutdown in progress' wid-#{
                 worker.process_wid
               }"

      assert_receive :fetch
    end

    test "should set state to ':running_job' when there is a job to process" do
      start_supervised!({FaktoryWorker.JobSupervisor, name: FaktoryWorker})

      job =
        Jason.encode!(%{
          "args" => [%{"hey" => "there!"}],
          "created_at" => "2019-04-09T12:14:07.6550641Z",
          "enqueued_at" => "2019-04-09T12:14:07.6550883Z",
          "jid" => "f47ccc395ef9d9646118434f",
          "jobtype" => "FaktoryWorker.TestQueueWorker",
          "queue" => "test_queue"
        })

      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, "FETCH test_queue\r\n" ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:ok, "$#{byte_size(job)}\r\n"}
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _, _ ->
        {:ok, "#{job}\r\n"}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      result =
        opts
        |> Worker.new()
        |> Worker.send_fetch()

      assert result.worker_state == :running_job

      :ok = stop_supervised(FaktoryWorker_job_supervisor)
    end

    test "should run the returned job in a new process" do
      start_supervised!({FaktoryWorker.JobSupervisor, name: FaktoryWorker})

      job =
        Jason.encode!(%{
          "args" => [%{"hey" => "there!", "_send_to_" => inspect(self())}],
          "created_at" => "2019-04-09T12:14:07.6550641Z",
          "enqueued_at" => "2019-04-09T12:14:07.6550883Z",
          "jid" => "f47ccc395ef9d9646118434f",
          "jobtype" => "FaktoryWorker.TestQueueWorker",
          "queue" => "test_queue"
        })

      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, "FETCH test_queue\r\n" ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:ok, "$#{byte_size(job)}\r\n"}
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _, _ ->
        {:ok, "#{job}\r\n"}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      result =
        opts
        |> Worker.new()
        |> Worker.send_fetch()

      assert %Task{} = result.job_ref
      assert result.job_id == "f47ccc395ef9d9646118434f"

      assert result.job == %{
               "args" => [%{"hey" => "there!", "_send_to_" => inspect(self())}],
               "created_at" => "2019-04-09T12:14:07.6550641Z",
               "enqueued_at" => "2019-04-09T12:14:07.6550883Z",
               "jid" => "f47ccc395ef9d9646118434f",
               "jobtype" => "FaktoryWorker.TestQueueWorker",
               "queue" => "test_queue"
             }

      assert is_reference(result.job_timeout_ref)

      assert_receive {FaktoryWorker.TestQueueWorker, :perform, %{"hey" => "there!"}}, 50

      :ok = stop_supervised(FaktoryWorker_job_supervisor)
    end
  end

  describe "stop_job/1" do
    defp new_worker_with_job(opts) do
      job_ref =
        Task.Supervisor.async_nolink(
          FaktoryWorker_job_supervisor,
          fn -> Process.sleep(10_000) end,
          shutdown: :brutal_kill
        )

      opts
      |> Worker.new()
      |> Map.put(:job_ref, job_ref)
      |> Map.put(:job_id, "f47ccc395ef9d9646118434f")
      |> Map.put(:job, %{"jid" => "f47ccc395ef9d9646118434f"})
      |> Map.put(:job_timeout_ref, :erlang.make_ref())
    end

    test "should stop the job process" do
      start_supervised!({FaktoryWorker.JobSupervisor, name: FaktoryWorker})

      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, _ ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:ok, "+OK\r\n"}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["timeout_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      worker = new_worker_with_job(opts)
      Worker.stop_job(worker)

      refute Process.alive?(worker.job_ref.pid)

      :ok = stop_supervised(FaktoryWorker_job_supervisor)
    end

    test "should send the 'FAIL' command" do
      start_supervised!({FaktoryWorker.JobSupervisor, name: FaktoryWorker})

      fail_payload =
        Jason.encode!(%{
          backtrace: [],
          errtype: "Undetected Error Type",
          jid: "f47ccc395ef9d9646118434f",
          message: "\"Job Timeout\""
        })

      fail_command = "FAIL #{fail_payload}\r\n"

      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, ^fail_command ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:ok, "+OK\r\n"}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["timeout_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      opts
      |> new_worker_with_job()
      |> Worker.stop_job()

      :ok = stop_supervised(FaktoryWorker_job_supervisor)
    end

    test "should return the updated worker state" do
      start_supervised!({FaktoryWorker.JobSupervisor, name: FaktoryWorker})

      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, _ ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:ok, "+OK\r\n"}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["timeout_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      state =
        opts
        |> new_worker_with_job()
        |> Worker.stop_job()

      assert state.job_id == nil
      assert state.job_ref == nil
      assert state.job_timeout_ref == nil

      :ok = stop_supervised(FaktoryWorker_job_supervisor)
    end

    test "should handle the job already having completed" do
      worker_connection_mox()

      opts = [
        process_wid: Random.process_wid(),
        queues: ["timeout_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      worker = Worker.new(opts)
      new_state = Worker.stop_job(worker)

      assert worker == new_state
    end

    test "should cancel the job timeout timer" do
      start_supervised!({FaktoryWorker.JobSupervisor, name: FaktoryWorker})

      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, _ ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:ok, "+OK\r\n"}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["timeout_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      timer_ref = Process.send_after(self(), :test_message, 5000)

      worker =
        opts
        |> new_worker_with_job()
        |> Map.put(:job_timeout_ref, timer_ref)
        |> Worker.stop_job()

      assert worker.job_timeout_ref == nil
      assert Process.cancel_timer(timer_ref) == false

      :ok = stop_supervised(FaktoryWorker_job_supervisor)
    end
  end

  describe "ack_job/2" do
    defp new_running_worker(opts, %{"jid" => jid} = job) do
      opts
      |> Worker.new()
      |> Map.put(:job_id, jid)
      |> Map.put(:job_ref, :erlang.make_ref())
      |> Map.put(:job, job)
      |> Map.put(:worker_state, :running_job)
    end

    test "should send a successful 'ACK' to faktory" do
      job_id = Random.string()
      job = %{"jid" => job_id}

      ack_command = "ACK {\"jid\":\"#{job_id}\"}\r\n"

      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, ^ack_command ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:ok, "+OK\r\n"}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      result =
        opts
        |> new_running_worker(job)
        |> Worker.ack_job(:ok)

      assert result.worker_state == :ok
      assert result.job_ref == nil
      assert result.job_id == nil
      assert result.job_timeout_ref == nil
    end

    test "should log that a successful 'ACK' was sent to faktory" do
      job_id = Random.string()
      job = %{"jid" => job_id}

      ack_command = "ACK {\"jid\":\"#{job_id}\"}\r\n"

      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, ^ack_command ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:ok, "+OK\r\n"}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      log_message =
        capture_log(fn ->
          opts
          |> new_running_worker(job)
          |> Worker.ack_job(:ok)
        end)

      assert log_message =~ "Succeeded jid-#{job_id}"
    end

    test "should schedule the next fetch for a successful ack" do
      job_id = Random.string()
      job = %{"jid" => job_id}

      ack_command = "ACK {\"jid\":\"#{job_id}\"}\r\n"

      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, ^ack_command ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:ok, "+OK\r\n"}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      opts
      |> new_running_worker(job)
      |> Worker.ack_job(:ok)

      assert_receive :fetch
    end

    test "should send a 'FAIL' to faktory for an unsuccessful job" do
      job_id = Random.string()
      job = %{"jid" => job_id}

      {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)

      fail_payload = %{
        jid: job_id,
        errtype: "Elixir.RuntimeError",
        message: "It went bang!",
        backtrace: Enum.map(stacktrace, &Exception.format_stacktrace_entry/1)
      }

      fail_command = "FAIL #{Jason.encode!(fail_payload)}\r\n"

      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, ^fail_command ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:ok, "+OK\r\n"}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        disable_fetch: true,
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      error = {%RuntimeError{message: "It went bang!"}, stacktrace}

      result =
        opts
        |> new_running_worker(job)
        |> Worker.ack_job({:error, error})

      assert result.worker_state == :ok
      assert result.job_ref == nil
      assert result.job_id == nil
      assert result.job == nil
      assert result.job_timeout_ref == nil
    end

    test "should log that a 'FAIL' was sent to faktory" do
      job_id = Random.string()
      job = %{"jid" => job_id}

      {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)

      fail_payload = %{
        jid: job_id,
        errtype: "Elixir.RuntimeError",
        message: "It went bang!",
        backtrace: Enum.map(stacktrace, &Exception.format_stacktrace_entry/1)
      }

      fail_command = "FAIL #{Jason.encode!(fail_payload)}\r\n"

      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, ^fail_command ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:ok, "+OK\r\n"}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        disable_fetch: true,
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      error = {%RuntimeError{message: "It went bang!"}, stacktrace}

      log_message =
        capture_log(fn ->
          opts
          |> new_running_worker(job)
          |> Worker.ack_job({:error, error})
        end)

      assert log_message =~ "Failed jid-#{job_id}"
    end

    test "should schedule the next fetch for an unsuccessful ack" do
      job_id = Random.string()
      job = %{"jid" => job_id}

      {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)

      fail_payload = %{
        jid: job_id,
        errtype: "Elixir.RuntimeError",
        message: "It went bang!",
        backtrace: Enum.map(stacktrace, &Exception.format_stacktrace_entry/1)
      }

      fail_command = "FAIL #{Jason.encode!(fail_payload)}\r\n"

      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, ^fail_command ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:ok, "+OK\r\n"}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      error = {%RuntimeError{message: "It went bang!"}, stacktrace}

      opts
      |> new_running_worker(job)
      |> Worker.ack_job({:error, error})

      assert_receive :fetch
    end

    test "should log when there was an error sending the ack" do
      job_id = Random.string()
      job = %{"jid" => job_id}

      ack_command = "ACK {\"jid\":\"#{job_id}\"}\r\n"

      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, ^ack_command ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:error, :closed}
      end)

      # the connection manager retries a failed request once
      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, ^ack_command ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:error, :closed}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      log_message =
        capture_log(fn ->
          opts
          |> new_running_worker(job)
          |> Worker.ack_job(:ok)
        end)

      consume_initial_fetch_message()

      assert log_message =~
               "Error sending 'ACK' acknowledgement to faktory"

      assert_receive :fetch
    end

    test "should log when there was an error sending the fail" do
      job_id = Random.string()
      job = %{"jid" => job_id}

      fail_payload = %{
        jid: job_id,
        errtype: "Undetected Error Type",
        message: "exit",
        backtrace: []
      }

      fail_command = "FAIL #{Jason.encode!(fail_payload)}\r\n"

      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, ^fail_command ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:error, :closed}
      end)

      # the connection manager retries a failed request one more time
      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, ^fail_command ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:error, :closed}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      log_message =
        capture_log(fn ->
          opts
          |> new_running_worker(job)
          |> Worker.ack_job({:error, :exit})
        end)

      consume_initial_fetch_message()

      assert log_message =~
               "Error sending 'FAIL' acknowledgement to faktory"

      assert_receive :fetch
    end

    test "should cancel the job timeout when acknowledging a successful job" do
      job_id = Random.string()
      job = %{"jid" => job_id}

      ack_command = "ACK {\"jid\":\"#{job_id}\"}\r\n"

      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, ^ack_command ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:ok, "+OK\r\n"}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        disable_fetch: true,
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      timer_ref = Process.send_after(self(), :test_message, 5000)

      result =
        opts
        |> new_running_worker(job)
        |> Map.put(:job_timeout_ref, timer_ref)
        |> Worker.ack_job(:ok)

      assert result.job_timeout_ref == nil
      assert Process.cancel_timer(timer_ref) == false
    end

    test "should cancel the job timeout when acknowledging a failed job" do
      job_id = Random.string()
      job = %{"jid" => job_id}

      {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)

      fail_payload = %{
        jid: job_id,
        errtype: "Elixir.RuntimeError",
        message: "It went bang!",
        backtrace: Enum.map(stacktrace, &Exception.format_stacktrace_entry/1)
      }

      fail_command = "FAIL #{Jason.encode!(fail_payload)}\r\n"

      worker_connection_mox()

      expect(FaktoryWorker.SocketMock, :send, fn _, ^fail_command ->
        :ok
      end)

      expect(FaktoryWorker.SocketMock, :recv, fn _ ->
        {:ok, "+OK\r\n"}
      end)

      opts = [
        process_wid: Random.process_wid(),
        queues: ["test_queue"],
        disable_fetch: true,
        connection: [socket_handler: FaktoryWorker.SocketMock]
      ]

      error = {%RuntimeError{message: "It went bang!"}, stacktrace}
      timer_ref = Process.send_after(self(), :test_message, 5000)

      result =
        opts
        |> new_running_worker(job)
        |> Map.put(:job_timeout_ref, timer_ref)
        |> Worker.ack_job({:error, error})

      assert result.job_timeout_ref == nil
      assert Process.cancel_timer(timer_ref) == false
    end
  end

  defp consume_initial_fetch_message() do
    # calling Worker.new/1 schedules an initial fetch
    receive do
      :fetch -> :ok
    after
      1 -> :error
    end
  end
end
