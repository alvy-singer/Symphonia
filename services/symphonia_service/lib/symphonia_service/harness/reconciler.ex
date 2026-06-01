defmodule SymphoniaService.Harness.Reconciler do
  @moduledoc """
  Reconciles private run records with public task state before Harness dispatch.
  """

  alias SymphoniaService.{RepositoryRegistry, TaskStore}
  alias SymphoniaService.CodingAssistant.{RunEvents, RunStore}
  alias SymphoniaService.Harness.{DecisionLog, RetryPolicy}

  @queued_stale_after_ms 10 * 60 * 1_000
  @running_stale_after_ms 60 * 60 * 1_000
  @heartbeat_stale_after_ms 10 * 60 * 1_000

  def reconcile(registry_path, opts \\ []) do
    now = DateTime.utc_now()
    thresholds = thresholds(opts)
    repositories = RepositoryRegistry.list(registry_path)
    repositories_by_key = Map.new(repositories, &{&1["key"], &1})

    run_decisions =
      RunStore.list()
      |> Enum.flat_map(&reconcile_run(&1, repositories_by_key, thresholds, now))

    task_decisions =
      repositories
      |> Enum.flat_map(&reconcile_tasks(&1))

    decisions = run_decisions ++ task_decisions

    %{
      decisions: decisions,
      summary: %{
        "at" => iso8601(now),
        "reconciled" => length(decisions),
        "stale" =>
          Enum.count(decisions, &(&1["code"] in ["stale_run_failed", "missing_workspace_failed"]))
      }
    }
  end

  def counts(registry_path, opts \\ []) do
    now = DateTime.utc_now()
    thresholds = thresholds(opts)
    repositories_by_key = registry_path |> RepositoryRegistry.list() |> Map.new(&{&1["key"], &1})
    runs = RunStore.list()

    %{
      "activeRuns" => Enum.count(runs, &RunEvents.active?/1),
      "staleRuns" =>
        Enum.count(runs, fn run ->
          RunEvents.active?(run) and
            stale_reason(run, repositories_by_key[run["repository"]], nil, thresholds, now) != nil
        end),
      "retryScheduled" => Enum.count(runs, &RetryPolicy.scheduled?/1)
    }
  rescue
    _error -> %{"activeRuns" => 0, "staleRuns" => 0, "retryScheduled" => 0}
  end

  def thresholds(opts \\ []) do
    %{
      queued_stale_after_ms: Keyword.get(opts, :queued_stale_after_ms, @queued_stale_after_ms),
      running_stale_after_ms: Keyword.get(opts, :running_stale_after_ms, @running_stale_after_ms),
      heartbeat_stale_after_ms:
        Keyword.get(opts, :heartbeat_stale_after_ms, @heartbeat_stale_after_ms)
    }
  end

  defp reconcile_run(run, repositories_by_key, thresholds, now) do
    if RunEvents.active?(run) do
      repository = repositories_by_key[run["repository"]]
      task = if repository, do: TaskStore.get_task(repository, run["task"])

      cond do
        repository == nil ->
          failed =
            RunStore.mark_failed(run, missing_repository_message(), missing_repository_message())

          [
            DecisionLog.reconcile(
              run["repository"],
              run["task"],
              "missing_repository_failed",
              missing_repository_message(),
              run_id: failed["id"]
            )
          ]

        task == nil ->
          failed = RunStore.mark_failed(run, missing_task_message(), missing_task_message())

          [
            DecisionLog.reconcile(
              repository,
              run["task"],
              "missing_task_failed",
              missing_task_message(),
              run_id: failed["id"]
            )
          ]

        handoff_exists?(task) ->
          message = "Run was marked failed because the task already has a review handoff."
          failed = RunStore.mark_failed(run, message, message)

          TaskStore.patch_task(repository, task["key"], %{
            "frontmatter" => %{"run" => run_frontmatter(failed)}
          })

          [
            DecisionLog.reconcile(repository, task, "handoff_preserved", message,
              run_id: failed["id"]
            )
          ]

        task_run_id(task) not in [nil, run["id"]] ->
          message = "Run was marked failed because task metadata points to another run."
          failed = RunStore.mark_failed(run, message, message)

          [
            DecisionLog.reconcile(repository, task, "run_task_mismatch_failed", message,
              run_id: failed["id"]
            )
          ]

        reason = stale_reason(run, repository, task, thresholds, now) ->
          {paused_reason, code, message} = reason
          failed = RunStore.mark_failed(run, message, message)
          pause_task_with_run(repository, task, failed, paused_reason, message)

          [
            DecisionLog.reconcile(repository, task, code, message, run_id: failed["id"])
          ]

        true ->
          []
      end
    else
      []
    end
  end

  defp reconcile_tasks(repository) do
    repository
    |> TaskStore.list_tasks()
    |> Enum.flat_map(fn task ->
      case task["run"] do
        %{"id" => run_id, "state" => state} when state in ["queued", "running"] ->
          case RunStore.get(run_id) do
            nil ->
              message = "Run was marked failed because its private run metadata is missing."

              task =
                TaskStore.apply_event(repository, task["key"], "fail_run", %{
                  "explanation" => message
                })

              failed_run = failed_task_run_frontmatter(task, message)

              TaskStore.patch_task(repository, task["key"], %{
                "frontmatter" => %{"run" => failed_run}
              })

              [
                DecisionLog.reconcile(repository, task, "missing_run_metadata", message,
                  run_id: run_id
                )
              ]

            %{"state" => terminal} = run when terminal in ["completed", "failed", "canceled"] ->
              TaskStore.patch_task(repository, task["key"], %{
                "frontmatter" => %{"run" => run_frontmatter(run)}
              })

              [
                DecisionLog.reconcile(
                  repository,
                  task,
                  "task_run_frontmatter_refreshed",
                  "Task run metadata was refreshed from the private run store.",
                  run_id: run_id
                )
              ]

            _run ->
              []
          end

        _run ->
          []
      end
    end)
  end

  defp stale_reason(run, _repository, _task, thresholds, now) do
    cond do
      missing_workspace?(run) ->
        {"blocked_by_setup", "missing_workspace_failed",
         "Run was marked failed because its local workspace is missing."}

      run["state"] == "queued" and
          stale_since?(
            run["created_at"] || run["updated_at"],
            thresholds.queued_stale_after_ms,
            now
          ) ->
        {"run_failed", "stale_run_failed",
         "Run was marked failed because it stayed queued for too long."}

      run["state"] == "running" and
          stale_since?(
            run["started_at"] || run["updated_at"],
            thresholds.running_stale_after_ms,
            now
          ) ->
        {"run_failed", "stale_run_failed", "Run was marked failed because it stopped updating."}

      stale_since?(run["updated_at"], thresholds.heartbeat_stale_after_ms, now) ->
        {"run_failed", "stale_run_failed", "Run was marked failed because it stopped updating."}

      true ->
        nil
    end
  end

  defp stale_since?(nil, _threshold_ms, _now), do: false

  defp stale_since?(value, threshold_ms, now) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} -> DateTime.diff(now, timestamp, :second) * 1_000 >= threshold_ms
      _ -> false
    end
  end

  defp stale_since?(_value, _threshold_ms, _now), do: false

  defp missing_workspace?(%{"workspace_path" => path}) when is_binary(path) do
    String.trim(path) != "" and not File.dir?(path)
  end

  defp missing_workspace?(_run), do: false

  defp pause_task_with_run(repository, task, run, paused_reason, message) do
    TaskStore.apply_event(repository, task["key"], "fail_run", %{
      "explanation" => message,
      "paused_reason" => paused_reason
    })

    TaskStore.patch_task(repository, task["key"], %{
      "frontmatter" => %{"run" => run_frontmatter(run)}
    })
  end

  defp failed_task_run_frontmatter(task, message) do
    now = iso8601(DateTime.utc_now())

    (get_in(task, [:frontmatter, "run"]) || %{})
    |> Map.merge(%{
      "state" => "failed",
      "current_step" => RunEvents.default_step("failed"),
      "message" => message,
      "display_step" => "Run failed",
      "display_message" => message,
      "completed_at" => now
    })
  end

  defp run_frontmatter(run) do
    %{
      "id" => run["id"],
      "kind" => run["kind"],
      "state" => run["state"],
      "current_step" => RunEvents.display_step(run),
      "message" => RunEvents.public_message(run),
      "display_step" => RunEvents.display_step(run),
      "display_message" => RunEvents.display_message(run),
      "eligibility_reason" => run["eligibility_reason"],
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
    |> reject_nil()
  end

  defp task_run_id(task),
    do: get_in(task, ["run", "id"]) || get_in(task, [:frontmatter, "run", "id"])

  defp handoff_exists?(%{"handoff" => handoff}) when is_map(handoff), do: map_size(handoff) > 0
  defp handoff_exists?(_task), do: false

  defp missing_repository_message,
    do: "Run was marked failed because its repository is no longer registered."

  defp missing_task_message, do: "Run was marked failed because its task is missing."

  defp reject_nil(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
  defp iso8601(datetime), do: datetime |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
