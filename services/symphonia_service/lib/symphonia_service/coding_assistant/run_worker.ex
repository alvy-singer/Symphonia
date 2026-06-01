defmodule SymphoniaService.CodingAssistant.RunWorker do
  @moduledoc """
  Executes one background Coding Assistant run.
  """

  use GenServer

  alias SymphoniaService.CodingAssistant.{
    AppServerClient,
    FailureClass,
    HandoffBuilder,
    RunEvents,
    RunRegistry,
    RunStore
  }

  alias SymphoniaService.Access.{Actor, AuditLog}
  alias SymphoniaService.Harness.RetryPolicy
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

    audit_run_outcome(state, run, "run.canceled")
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
    repository = private_repository(state["repository"], state["registry_path"])
    task_key = state["task_key"]
    run = RunStore.mark_step(state["run"], "Running Coding Assistant")
    task = TaskStore.get_task(repository, task_key)
    params = provider_params(state)

    case state["provider"].run(repository, task, run, params) do
      {:ok, handoff} ->
        run = RunStore.mark_step(run, "Writing handoff")
        completed_run = RunStore.mark_completed(run, handoff)
        task = HandoffBuilder.apply(repository, task_key, completed_run, handoff)
        audit_run_outcome(state, completed_run, "run.completed")
        {:done, completed_run, task}

      {:error, reason} ->
        handle_provider_error(state, run, reason)
    end
  end

  defp private_repository(repository, registry_path) when is_binary(registry_path) do
    Map.put(repository, "_registry_path", registry_path)
  end

  defp private_repository(repository, _registry_path), do: repository

  defp handle_provider_error(%{"kind" => "daemon_assignment"} = state, run, reason) do
    public_message = failure_explanation_for_state(state, reason)
    failed_run = mark_provider_failed(state, run, reason, public_message)

    case RetryPolicy.schedule(failed_run, reason, public_message) do
      {:retry, attrs} ->
        retry_run = RunStore.update_metadata(failed_run, attrs)
        task = fail_task(state, retry_run, attrs["message"], "waiting_for_sync")
        {:done, retry_run, task}

      {:exhausted, attrs} ->
        retry_run = RunStore.update_metadata(failed_run, attrs)
        task = fail_task(state, retry_run, attrs["message"], "run_failed")
        {:done, retry_run, task}

      {:no_retry, attrs} ->
        failed_run = RunStore.update_metadata(failed_run, attrs)
        task = fail_task(state, failed_run, public_message, paused_reason_for(public_message))
        {:done, failed_run, task}
    end
  end

  defp handle_provider_error(%{"kind" => "review_continuation"} = state, run, reason) do
    attempt = state["attempt"]
    max_attempts = state["max_attempts"]
    public_message = failure_explanation_for_state(state, reason)
    failed_run = mark_provider_failed(state, run, reason, public_message)

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
    paused_reason = paused_reason_for(public_message)
    pause_task_for_failure(state, public_message, paused_reason)
    failed_run = mark_provider_failed(state, run, reason, public_message)
    task = fail_task(state, failed_run, public_message, paused_reason)
    {:done, failed_run, task}
  end

  defp fail_run(state, run, reason) do
    public_message = failure_explanation_for_state(state, reason)
    failed_run = mark_provider_failed(state, run, reason, public_message)
    fail_task(state, failed_run, public_message)
    failed_run
  end

  defp mark_provider_failed(state, run, reason, public_message) do
    failure_class =
      if provider = state["provider"] do
        provider.classify_failure(reason, %{
          "kind" => state["kind"],
          "public_message" => public_message,
          "run" => run
        })
        |> FailureClass.normalize()
      else
        "unknown"
      end

    run
    |> RunStore.mark_failed(reason, public_message)
    |> RunStore.update_metadata(%{"failure_class" => failure_class})
  rescue
    _error ->
      run
      |> RunStore.mark_failed(reason, public_message)
      |> RunStore.update_metadata(%{"failure_class" => "unknown"})
  end

  defp fail_task(state, run, public_message) do
    fail_task(state, run, public_message, paused_reason_for(public_message))
  end

  defp fail_task(state, run, public_message, paused_reason) do
    state["repository"]
    |> TaskStore.apply_event(state["task_key"], "fail_run", %{
      "explanation" => public_message,
      "paused_reason" => paused_reason
    })
    |> then(fn _task -> put_task_run(state["repository"], state["task_key"], run) end)
    |> tap(fn _task ->
      action =
        if paused_reason == "waiting_for_sync", do: "run.retry_scheduled", else: "run.failed"

      audit_run_outcome(state, run, action)
    end)
  end

  defp pause_task_for_failure(state, public_message, paused_reason) do
    TaskStore.apply_event(state["repository"], state["task_key"], "fail_run", %{
      "explanation" => public_message,
      "paused_reason" => paused_reason
    })
  end

  defp audit_run_outcome(state, run, action) do
    AuditLog.record(state["registry_path"], state["repository"], %{
      "actor" => actor_for_run(run),
      "action" => action,
      "target" => %{"type" => "task", "id" => state["task_key"]},
      "result" => if(action == "run.failed", do: "failed", else: "completed"),
      "metadata" => %{
        "runId" => run["id"],
        "taskKey" => state["task_key"],
        "provider" => run["provider"],
        "workspaceProvider" => run["workspace_provider"],
        "reviewBranch" => run["review_branch"],
        "reasonCode" => run["failure_class"]
      }
    })
  rescue
    _error -> :ok
  end

  defp actor_for_run(%{"kind" => "daemon_assignment"}), do: Actor.harness()
  defp actor_for_run(_run), do: Actor.default()

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
      "kind" => run["kind"],
      "state" => run["state"],
      "current_step" => run["current_step"],
      "message" => RunEvents.public_message(run),
      "display_step" => RunEvents.display_step(run),
      "display_message" => RunEvents.display_message(run),
      "eligibility_reason" => run["eligibility_reason"],
      "workspace_provider" => run["workspace_provider"],
      "cleanup_warning" => run["cleanup_warning"],
      "review_branch" => run["review_branch"],
      "curated_summary_id" => run["curated_summary_id"],
      "curated_summary_path" => run["curated_summary_path"],
      "evidence_ids" => run["evidence_ids"],
      "retry_at" => run["retry_at"],
      "failure_class" => run["failure_class"],
      "attempt" => run["attempt"],
      "max_attempts" => run["max_attempts"],
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
