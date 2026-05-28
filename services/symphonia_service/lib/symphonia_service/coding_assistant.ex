defmodule SymphoniaService.CodingAssistant do
  @moduledoc """
  Facade for assigning tasks to the background Coding Assistant.
  """

  alias SymphoniaService.Clarise.{ChecklistSerializer, FeedbackStructurer, ReviewNotesBuilder}

  alias SymphoniaService.CodingAssistant.{
    Cancellation,
    AppServerProvider,
    CodexProvider,
    LocalDemoProvider,
    RunEvents,
    RunStore,
    RunSupervisor
  }

  alias SymphoniaService.TaskStore

  @continuation_max_attempts 2

  def start_run(registry_path, repository, task_key, params \\ %{}) do
    task = get_task!(repository, task_key)
    ensure_assignable!(task)

    provider = provider()

    run =
      RunStore.create(%{
        "provider" => provider_id(provider),
        "repository" => repository["key"],
        "task" => task_key,
        "kind" => "assignment",
        "codex_thread_id" => previous_codex_thread_id(task)
      })

    TaskStore.apply_event(repository, task_key, "start")
    task = put_task_run(repository, task_key, run)

    {:ok, _pid} =
      RunSupervisor.start_run(%{
        "registry_path" => registry_path,
        "repository" => repository,
        "task_key" => task_key,
        "provider" => provider,
        "params" => params,
        "kind" => "assignment",
        "run" => run
      })

    %{"run" => RunStore.public(run), "task" => task}
  end

  def start_harness_run(registry_path, repository, task_key, params \\ %{}) do
    task = get_task!(repository, task_key)
    ensure_assignable!(task)

    provider = AppServerProvider

    run =
      RunStore.create(%{
        "provider" => provider_id(provider),
        "repository" => repository["key"],
        "task" => task_key,
        "kind" => "daemon_assignment",
        "eligibility_reason" => Map.get(params, "eligibility_reason"),
        "codex_thread_id" => previous_codex_thread_id(task)
      })

    TaskStore.apply_event(repository, task_key, "start")
    task = put_task_run(repository, task_key, run)

    {:ok, _pid} =
      RunSupervisor.start_run(%{
        "registry_path" => registry_path,
        "repository" => repository,
        "task_key" => task_key,
        "provider" => provider,
        "params" => params,
        "kind" => "daemon_assignment",
        "run" => run
      })

    %{"run" => RunStore.public(run), "task" => task}
  end

  def continue_from_review_notes(registry_path, repository, task_key, params \\ %{}) do
    task = get_task!(repository, task_key)
    ensure_reviewable!(task)

    feedback = required_feedback!(params)
    requested_changes = FeedbackStructurer.structure(feedback)

    if requested_changes == [] do
      raise ArgumentError, "Feedback must describe at least one requested change."
    end

    review_note = ReviewNotesBuilder.build(feedback, requested_changes)
    assistant_input = ChecklistSerializer.serialize(requested_changes)
    continuation = continuation_state(review_note["id"], 1)
    ReviewNotesBuilder.apply(repository, task_key, review_note, continuation)

    provider = provider()

    run =
      RunStore.create(%{
        "provider" => provider_id(provider),
        "repository" => repository["key"],
        "task" => task_key,
        "kind" => "review_continuation",
        "input" => assistant_input,
        "review_note_id" => review_note["id"],
        "attempt" => 1,
        "max_attempts" => @continuation_max_attempts,
        "codex_thread_id" => previous_codex_thread_id(task)
      })

    task = put_task_run(repository, task_key, run)

    {:ok, _pid} =
      RunSupervisor.start_run(%{
        "registry_path" => registry_path,
        "repository" => repository,
        "task_key" => task_key,
        "provider" => provider,
        "params" => params,
        "kind" => "review_continuation",
        "assistant_input" => assistant_input,
        "review_note_id" => review_note["id"],
        "attempt" => 1,
        "max_attempts" => @continuation_max_attempts,
        "run" => run
      })

    %{"review_note" => review_note, "run" => RunStore.public(run), "task" => task}
  end

  def get_run(repository, task_key, run_id) do
    case RunStore.get(run_id) do
      nil ->
        raise ArgumentError, "Run #{run_id} not found."

      run ->
        if run["repository"] == repository["key"] and run["task"] == task_key do
          RunStore.public(run)
        else
          raise ArgumentError, "Run #{run_id} does not belong to task #{task_key}."
        end
    end
  end

  def get_run_events(repository, task_key, run_id) do
    case RunStore.get(run_id) do
      nil ->
        raise ArgumentError, "Run #{run_id} not found."

      run ->
        if run["repository"] == repository["key"] and run["task"] == task_key do
          RunStore.public_events(run)
        else
          raise ArgumentError, "Run #{run_id} does not belong to task #{task_key}."
        end
    end
  end

  def get_run_progress_events(repository, task_key, run_id, opts \\ []) do
    case RunStore.get(run_id) do
      nil ->
        raise ArgumentError, "Run #{run_id} not found."

      run ->
        if run["repository"] == repository["key"] and run["task"] == task_key do
          RunStore.public_progress_events(run, opts)
        else
          raise ArgumentError, "Run #{run_id} does not belong to task #{task_key}."
        end
    end
  end

  def cancel_run(repository, task_key, run_id) do
    case RunStore.get(run_id) do
      nil ->
        raise ArgumentError, "Run #{run_id} not found."

      run ->
        if run["repository"] != repository["key"] or run["task"] != task_key do
          raise ArgumentError, "Run #{run_id} does not belong to task #{task_key}."
        else
          if RunEvents.terminal?(run) do
            %{"run" => RunStore.public(run), "task" => TaskStore.get_task(repository, task_key)}
          else
            case Cancellation.cancel(run_id) do
              {:ok, result} -> result
              {:error, reason} -> raise ArgumentError, reason
            end
          end
        end
    end
  end

  def recover_interrupted_runs(registry_path, opts \\ []) do
    RunSupervisor.recover_interrupted_runs(registry_path, opts)
  end

  defp get_task!(repository, task_key) do
    case TaskStore.get_task(repository, task_key) do
      nil -> raise ArgumentError, "task #{task_key} not found"
      task -> task
    end
  end

  defp ensure_assignable!(%{"status" => "todo"}), do: :ok
  defp ensure_assignable!(%{"status" => "paused", "pausedReason" => "run_failed"}), do: :ok
  defp ensure_assignable!(%{"status" => "paused", "pausedReason" => "blocked_by_setup"}), do: :ok
  defp ensure_assignable!(%{"status" => "paused", "pausedReason" => "waiting_for_user"}), do: :ok

  defp ensure_assignable!(_task) do
    raise ArgumentError,
          "Assign to Coding Assistant is available for To-do and Paused tasks."
  end

  defp ensure_reviewable!(%{"status" => "in_review"}), do: :ok

  defp ensure_reviewable!(_task) do
    raise ArgumentError, "Request changes is available for In Review tasks."
  end

  defp required_feedback!(params) do
    case Map.get(params, "feedback") do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: raise(ArgumentError, "Feedback is required."), else: value

      _ ->
        raise ArgumentError, "Feedback is required."
    end
  end

  defp continuation_state(review_note_id, attempt) do
    %{
      "attempt" => attempt,
      "max_attempts" => @continuation_max_attempts,
      "source_review_note_id" => review_note_id
    }
  end

  defp put_task_run(repository, task_key, run) do
    TaskStore.patch_task(repository, task_key, %{
      "frontmatter" => %{
        "assistant" => run["provider"] || "coding_assistant",
        "run" => run_frontmatter(run)
      }
    })
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
      "review_branch" => run["review_branch"],
      "curated_summary_path" => run["curated_summary_path"],
      "started_at" => run["started_at"],
      "completed_at" => run["completed_at"]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp provider do
    Application.get_env(:symphonia_service, :coding_assistant_provider) ||
      provider_from_env(System.get_env("SYMPHONIA_CODING_ASSISTANT_PROVIDER"))
  end

  defp provider_from_env("local_demo"), do: LocalDemoProvider
  defp provider_from_env("demo"), do: LocalDemoProvider
  defp provider_from_env("codex"), do: CodexProvider
  defp provider_from_env("codex_exec"), do: CodexProvider
  defp provider_from_env(_value), do: AppServerProvider

  defp provider_id(provider) do
    if Code.ensure_loaded?(provider) and function_exported?(provider, :id, 0) do
      provider.id()
    else
      "coding_assistant"
    end
  end

  defp previous_codex_thread_id(task) do
    latest_private_codex_thread_id(task) ||
      get_in(task, [:frontmatter, "run", "codex_thread_id"]) ||
      get_in(task, ["run", "codexThreadId"]) ||
      get_in(task, ["run", "codex_thread_id"])
  end

  defp latest_private_codex_thread_id(task) do
    RunStore.list()
    |> Enum.filter(fn run ->
      run["repository"] == task["repo"] and run["task"] == task["key"] and
        is_binary(run["codex_thread_id"]) and String.trim(run["codex_thread_id"]) != ""
    end)
    |> Enum.sort_by(&(&1["updated_at"] || &1["created_at"] || ""), :desc)
    |> List.first()
    |> case do
      nil -> nil
      run -> run["codex_thread_id"]
    end
  rescue
    _error -> nil
  end
end
