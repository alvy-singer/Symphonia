defmodule SymphoniaService.CodingAssistant.RunWorker do
  @moduledoc """
  Executes one background Coding Assistant run.
  """

  use GenServer

  alias SymphoniaService.CodingAssistant.{
    AppServerClient,
    HandoffBuilder,
    RunEvents,
    RunRegistry,
    RunStore
  }

  alias SymphoniaService.TaskStore

  @canceled_message "Run canceled. The task is paused. You can retry when ready."

  def child_spec(attrs) do
    %{
      id: {__MODULE__, attrs["run"]["id"]},
      start: {__MODULE__, :start_link, [attrs]},
      restart: :temporary
    }
  end

  def start_link(attrs) do
    GenServer.start_link(__MODULE__, attrs, name: RunRegistry.via(attrs["run"]["id"]))
  end

  def cancel(pid) when is_pid(pid), do: GenServer.call(pid, :cancel, 5_000)

  @impl true
  def init(attrs) do
    Process.flag(:trap_exit, true)
    {:ok, Map.put(attrs, "provider_task", nil), {:continue, :start}}
  end

  @impl true
  def handle_continue(:start, state) do
    run = RunStore.mark_running(state["run"])
    task = put_task_run(state["repository"], state["task_key"], run)

    provider_task =
      Task.async(fn ->
        state
        |> Map.merge(%{"run" => run, "task" => task})
        |> execute_attempts()
      end)

    {:noreply, %{state | "run" => run, "provider_task" => provider_task}}
  end

  @impl true
  def handle_call(:cancel, _from, state) do
    shutdown_provider_task(state["provider_task"])
    run = RunStore.mark_canceled(state["run"])

    task =
      state["repository"]
      |> TaskStore.apply_event(state["task_key"], "pause_run", %{
        "explanation" => @canceled_message
      })
      |> then(fn _task -> put_task_run(state["repository"], state["task_key"], run) end)

    {:stop, :normal, {:ok, %{"run" => RunStore.public(run), "task" => task}}, state}
  end

  @impl true
  def handle_info({ref, {:ok, run, task}}, %{"provider_task" => %{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:stop, :normal, state |> Map.merge(%{"run" => run, "task" => task, "provider_task" => nil})}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{"provider_task" => %{ref: ref}} = state) do
    run =
      fail_run(state, state["run"], "The Coding Assistant process stopped: #{inspect(reason)}")

    {:stop, :normal, %{state | "run" => run, "provider_task" => nil}}
  end

  def handle_info({:EXIT, _pid, :normal}, state), do: {:noreply, state}
  def handle_info({:EXIT, _pid, :killed}, state), do: {:noreply, state}
  def handle_info(_message, state), do: {:noreply, state}

  defp execute_attempts(state) do
    case run_once(state) do
      {:retry, next_state} -> execute_attempts(next_state)
      {:done, run, task} -> {:ok, run, task}
    end
  end

  defp run_once(state) do
    repository = state["repository"]
    task_key = state["task_key"]
    run = RunStore.mark_step(state["run"], "Running Coding Assistant")
    task = TaskStore.get_task(repository, task_key)
    params = provider_params(state)

    case state["provider"].run(repository, task, run, params) do
      {:ok, handoff} ->
        run = RunStore.mark_step(run, "Writing handoff")
        completed_run = RunStore.mark_completed(run, handoff)
        task = HandoffBuilder.apply(repository, task_key, completed_run, handoff)
        {:done, completed_run, task}

      {:error, reason} ->
        handle_provider_error(state, run, reason)
    end
  end

  defp handle_provider_error(%{"kind" => "review_continuation"} = state, run, reason) do
    attempt = state["attempt"]
    max_attempts = state["max_attempts"]
    public_message = failure_explanation_for_state(state, reason)
    failed_run = RunStore.mark_failed(run, reason, public_message)

    cond do
      AppServerClient.setup_blocker?(public_message) ->
        task = fail_task(state, failed_run, public_message)
        {:done, failed_run, task}

      attempt < max_attempts ->
        next_attempt = attempt + 1

        TaskStore.patch_task(state["repository"], state["task_key"], %{
          "frontmatter" => %{
            "run" => run_frontmatter(failed_run),
            "review_continuation" =>
              continuation_state(state["review_note_id"], next_attempt, max_attempts)
          }
        })

        next_run =
          RunStore.create(%{
            "provider" => failed_run["provider"],
            "repository" => failed_run["repository"],
            "task" => failed_run["task"],
            "kind" => "review_continuation",
            "input" => state["assistant_input"],
            "review_note_id" => state["review_note_id"],
            "attempt" => next_attempt,
            "max_attempts" => max_attempts
          })
          |> RunStore.mark_running()

        put_task_run(state["repository"], state["task_key"], next_run)

        {:retry, %{state | "run" => next_run, "attempt" => next_attempt}}

      true ->
        task = fail_task(state, failed_run, public_message)
        {:done, failed_run, task}
    end
  end

  defp handle_provider_error(state, run, reason) do
    public_message = failure_explanation_for_state(state, reason)
    failed_run = RunStore.mark_failed(run, reason, public_message)
    task = fail_task(state, failed_run, public_message)
    {:done, failed_run, task}
  end

  defp fail_run(state, run, reason) do
    public_message = failure_explanation_for_state(state, reason)
    failed_run = RunStore.mark_failed(run, reason, public_message)
    fail_task(state, failed_run, public_message)
    failed_run
  end

  defp fail_task(state, run, public_message) do
    state["repository"]
    |> TaskStore.apply_event(state["task_key"], "fail_run", %{
      "explanation" => public_message,
      "paused_reason" => paused_reason_for(public_message)
    })
    |> then(fn _task -> put_task_run(state["repository"], state["task_key"], run) end)
  end

  defp put_task_run(repository, task_key, run) do
    TaskStore.patch_task(repository, task_key, %{
      "frontmatter" => %{
        "assistant" => run["provider"] || "coding_assistant",
        "run" => run_frontmatter(run)
      }
    })
  end

  defp provider_params(state) do
    params = state["params"] || %{}

    if state["kind"] == "review_continuation" do
      %{
        "assistant_input" => state["assistant_input"],
        "review_note_id" => state["review_note_id"],
        "continuation" => true,
        "forceFailure" => force_failure?(params, state["attempt"])
      }
    else
      params
    end
  end

  defp force_failure?(params, attempt) do
    cond do
      Map.get(params, "forceFailure") == true or Map.get(params, "force_failure") == true ->
        true

      Map.get(params, "forceFailureOnce") == true or Map.get(params, "force_failure_once") == true ->
        attempt == 1

      is_integer(Map.get(params, "forceFailureAttempts")) ->
        attempt <= Map.get(params, "forceFailureAttempts")

      is_integer(Map.get(params, "force_failure_attempts")) ->
        attempt <= Map.get(params, "force_failure_attempts")

      true ->
        false
    end
  end

  defp continuation_state(review_note_id, attempt, max_attempts) do
    %{
      "attempt" => attempt,
      "max_attempts" => max_attempts,
      "source_review_note_id" => review_note_id
    }
  end

  defp run_frontmatter(run) do
    %{
      "id" => run["id"],
      "state" => run["state"],
      "current_step" => run["current_step"],
      "message" => RunEvents.public_message(run),
      "display_step" => RunEvents.display_step(run),
      "display_message" => RunEvents.display_message(run),
      "eligibility_reason" => run["eligibility_reason"],
      "review_branch" => run["review_branch"],
      "curated_summary_path" => run["curated_summary_path"],
      "started_at" => run["started_at"],
      "completed_at" => run["completed_at"]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp failure_explanation_for_state(%{"kind" => "review_continuation"}, reason) do
    failure_explanation(
      reason,
      "The Coding Assistant could not produce a new handoff after your requested changes."
    )
  end

  defp failure_explanation_for_state(_state, reason) do
    failure_explanation(reason, "The Coding Assistant could not produce a reviewable handoff.")
  end

  defp failure_explanation(reason, fallback) when is_binary(reason) do
    reason = String.trim(reason)

    if public_failure_reason?(reason) do
      reason
    else
      fallback
    end
  end

  defp failure_explanation(_reason, fallback), do: fallback

  defp public_failure_reason?("The Coding Assistant can't start" <> _rest), do: true
  defp public_failure_reason?("The Coding Assistant did not produce" <> _rest), do: true
  defp public_failure_reason?("The Coding Assistant could not finish" <> _rest), do: true
  defp public_failure_reason?("Codex App Server did not respond" <> _rest), do: true
  defp public_failure_reason?(reason), do: AppServerClient.setup_blocker?(reason)

  defp paused_reason_for(reason) do
    if AppServerClient.setup_blocker?(reason), do: "blocked_by_setup", else: "run_failed"
  end

  defp shutdown_provider_task(nil), do: :ok

  defp shutdown_provider_task(task) do
    Task.shutdown(task, :brutal_kill)
    :ok
  rescue
    _ -> :ok
  end
end
