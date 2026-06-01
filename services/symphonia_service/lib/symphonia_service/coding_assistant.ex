defmodule SymphoniaService.CodingAssistant do
  @moduledoc """
  Facade for assigning tasks to the background Coding Assistant.
  """

  alias SymphoniaService.Clarise.{ChecklistSerializer, FeedbackStructurer, ReviewNotesBuilder}

  alias SymphoniaService.CodingAssistant.{
    Cancellation,
    AppServerProvider,
    CodexProvider,
    GeminiCliProvider,
    LocalDemoProvider,
    ProviderCatalog,
    RunEvents,
    RunStore,
    RunSupervisor
  }

  alias SymphoniaService.Access.{Actor, AuditLog}
  alias SymphoniaService.Runner.CloudSandboxProvider

  alias SymphoniaService.Runners.{
    Assignments,
    AssignmentStore,
    LocalService,
    RepositoryPolicy,
    SelectionPolicy
  }

  alias SymphoniaService.Sandbox.Registry
  alias SymphoniaService.Sandbox.Policy, as: SandboxPolicy
  alias SymphoniaService.TaskStore

  @continuation_max_attempts 2

  def start_run(registry_path, repository, task_key, params \\ %{}) do
    task = get_task!(repository, task_key)
    ensure_assignable!(task)

    provider = provider(params)

    runner =
      if SandboxPolicy.requested?(params) do
        CloudSandboxProvider.runner_metadata(repository)
      else
        Map.get(params, "runner", LocalService.runner_metadata())
      end

    if remote_runner?(runner), do: Assignments.preflight(repository, task)
    if cloud_sandbox?(runner), do: sandbox_preflight!(registry_path, repository, task, params)
    provider_preflight!(registry_path, repository, task, params, provider, runner)

    run =
      RunStore.create(%{
        "provider" => provider_id(provider),
        "repository" => repository["key"],
        "task" => task_key,
        "kind" => "assignment",
        "runner" => runner,
        "execution_mode" => execution_mode_for(runner),
        "workspace_provider" => workspace_provider_for(runner),
        "codex_thread_id" => previous_codex_thread_id(task)
      })

    TaskStore.apply_event(repository, task_key, "start")
    task = put_task_run(repository, task_key, run)

    cond do
      remote_runner?(runner) ->
        actor = Map.get(params, "actor", Actor.default())

        {:ok, assignment} =
          Assignments.create_for_run(registry_path, repository, task, run, runner, actor, params)

        run =
          run
          |> RunStore.update_metadata(%{
            "assignment_id" => assignment["id"],
            "execution_mode" => "remote"
          })
          |> RunStore.mark_step("Queued for runner")

        task = put_task_run(repository, task_key, run)

        %{
          "run" => RunStore.public(run),
          "task" => task,
          "assignment" => AssignmentStore.public(assignment)
        }

      cloud_sandbox?(runner) ->
        actor = Map.get(params, "actor", Actor.default())

        {:ok, assignment} =
          Assignments.create_sandbox_for_run(
            registry_path,
            repository,
            task,
            run,
            runner,
            actor,
            params
          )

        run =
          run
          |> RunStore.update_metadata(%{
            "assignment_id" => assignment["id"],
            "execution_mode" => "cloud_sandbox",
            "workspace_provider" => "cloud_sandbox"
          })
          |> RunStore.mark_step("Creating sandbox")

        task = put_task_run(repository, task_key, run)

        {:ok, _pid} =
          CloudSandboxProvider.start(
            registry_path,
            repository,
            task,
            run,
            assignment,
            actor,
            params
          )

        %{
          "run" => RunStore.public(run),
          "task" => task,
          "assignment" => AssignmentStore.public(assignment)
        }

      true ->
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
  end

  def start_harness_run(registry_path, repository, task_key, params \\ %{}) do
    task = get_task!(repository, task_key)
    ensure_assignable!(task)

    provider = ProviderCatalog.harness_runnable_provider()
    {:ok, runner} = SelectionPolicy.select_for_run(registry_path, repository, Actor.harness())

    run =
      RunStore.create(%{
        "provider" => provider_id(provider),
        "repository" => repository["key"],
        "task" => task_key,
        "kind" => "daemon_assignment",
        "runner" => runner,
        "eligibility_reason" => Map.get(params, "eligibility_reason"),
        "attempt" => Map.get(params, "attempt", 0),
        "max_attempts" =>
          Map.get(params, "max_attempts", SymphoniaService.Harness.RetryPolicy.max_attempts()),
        "retry_of" => Map.get(params, "retry_of"),
        "retry_reason" => Map.get(params, "retry_reason"),
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
    if requested_provider_id(params) == "gemini_cli" do
      raise ArgumentError, "Gemini CLI is not available for review continuation in V1."
    end

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
        "runner" => Map.get(params, "runner", LocalService.runner_metadata()),
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

  def cancel_run(
        repository,
        task_key,
        run_id,
        registry_path \\ SymphoniaService.default_registry_path()
      ) do
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
            case Cancellation.cancel(run_id, registry_path, repository, task_key) do
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
  defp ensure_assignable!(%{"status" => "paused", "pausedReason" => "waiting_for_sync"}), do: :ok

  defp ensure_assignable!(_task) do
    raise ArgumentError,
          "Assign to Coding Assistant is available for To-do and Paused tasks."
  end

  defp ensure_reviewable!(%{"status" => "in_review", "githubPrState" => "open"}) do
    raise ArgumentError,
          "This task already has an open pull request. Request changes on the PR, or close the PR before continuing in Symphonia."
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
      "provider" => run["provider"],
      "current_step" => RunEvents.display_step(run),
      "message" => RunEvents.public_message(run),
      "display_step" => RunEvents.display_step(run),
      "display_message" => RunEvents.display_message(run),
      "eligibility_reason" => run["eligibility_reason"],
      "runner" => run["runner"],
      "execution_mode" => run["execution_mode"],
      "assignment_id" => run["assignment_id"],
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

  defp provider(params \\ %{}) do
    case requested_provider_id(params) do
      "gemini_cli" -> GeminiCliProvider
      "codex_app_server" -> AppServerProvider
      nil -> default_provider()
      _other -> raise ArgumentError, "Unsupported Coding Assistant provider."
    end
  end

  defp default_provider do
    Application.get_env(:symphonia_service, :coding_assistant_provider) ||
      provider_from_env(System.get_env("SYMPHONIA_CODING_ASSISTANT_PROVIDER"))
  end

  defp provider_from_env("local_demo"), do: LocalDemoProvider
  defp provider_from_env("demo"), do: LocalDemoProvider
  defp provider_from_env("codex"), do: CodexProvider
  defp provider_from_env("codex_exec"), do: CodexProvider
  defp provider_from_env(_value), do: AppServerProvider

  defp requested_provider_id(params) when is_map(params) do
    params["providerId"] || params["provider_id"]
  end

  defp requested_provider_id(_params), do: nil

  defp provider_id(provider) do
    if Code.ensure_loaded?(provider) and function_exported?(provider, :id, 0) do
      provider.id()
    else
      "coding_assistant"
    end
  end

  defp remote_runner?(%{"mode" => "remote_runner"}), do: true
  defp remote_runner?(_runner), do: false

  defp cloud_sandbox?(%{"mode" => "cloud_sandbox"}), do: true
  defp cloud_sandbox?(_runner), do: false

  defp execution_mode_for(%{"mode" => "remote_runner"}), do: "remote"
  defp execution_mode_for(%{"mode" => "cloud_sandbox"}), do: "cloud_sandbox"
  defp execution_mode_for(_runner), do: "local"

  defp workspace_provider_for(%{"mode" => "cloud_sandbox"}), do: "cloud_sandbox"
  defp workspace_provider_for(_runner), do: nil

  defp sandbox_preflight!(registry_path, repository, task, params) do
    actor = Map.get(params, "actor", Actor.default())
    readiness = Registry.readiness(repository, registry_path)

    AuditLog.record(registry_path, repository, %{
      "actor" => actor,
      "action" => "sandbox.provider_readiness_checked",
      "target" => %{"type" => "repository", "id" => repository["key"]},
      "result" => if(readiness["ready"] == true, do: "completed", else: "failed"),
      "metadata" => %{
        "provider" => SandboxPolicy.provider(repository),
        "workspaceProvider" => "cloud_sandbox",
        "reasonCode" => readiness["reason"]
      }
    })

    case SandboxPolicy.authorize_run(registry_path, repository, actor, task, params) do
      :ok ->
        :ok

      {:error, {_status, %{"error" => message} = payload}} ->
        audit_sandbox_denied(registry_path, repository, actor, task, payload["reasonCode"])
        raise ArgumentError, message

      {:error, reason} ->
        audit_sandbox_denied(registry_path, repository, actor, task, reason)
        raise ArgumentError, to_string(reason)
    end
  end

  defp provider_preflight!(
         registry_path,
         repository,
         task,
         params,
         GeminiCliProvider,
         %{"mode" => "cloud_sandbox"}
       ) do
    actor = Map.get(params, "actor", Actor.default())

    cond do
      not RepositoryPolicy.coding_assistant_provider_allowed?(repository, "gemini_cli") ->
        audit_provider_denied(registry_path, repository, actor, task, "provider_not_allowed")
        raise ArgumentError, "Gemini CLI is not allowed for this repository."

      GeminiCliProvider.readiness(registry_path: registry_path, repository: repository)["ready"] !=
          true ->
        audit_provider_denied(registry_path, repository, actor, task, "gemini_api_key_missing")
        raise ArgumentError, "Gemini CLI is not configured."

      SandboxPolicy.provider(repository) != "opensandbox" ->
        audit_provider_denied(
          registry_path,
          repository,
          actor,
          task,
          "sandbox_provider_not_allowed"
        )

        raise ArgumentError, "Gemini CLI requires OpenSandbox execution."

      true ->
        :ok
    end
  end

  defp provider_preflight!(registry_path, repository, task, params, GeminiCliProvider, _runner) do
    actor = Map.get(params, "actor", Actor.default())
    audit_provider_denied(registry_path, repository, actor, task, "gemini_requires_cloud_sandbox")
    raise ArgumentError, "Gemini CLI runs require cloud_sandbox execution in V1."
  end

  defp provider_preflight!(_registry_path, _repository, _task, _params, _provider, _runner),
    do: :ok

  defp audit_provider_denied(registry_path, repository, actor, task, reason) do
    AuditLog.record(registry_path, repository, %{
      "actor" => actor,
      "action" => "provider.gemini_cli_run_denied",
      "target" => %{"type" => "task", "id" => task["key"]},
      "result" => "denied",
      "metadata" => %{
        "taskKey" => task["key"],
        "provider" => "gemini_cli",
        "workspaceProvider" => "cloud_sandbox",
        "reasonCode" => reason
      }
    })

    :ok
  rescue
    _error -> :ok
  end

  defp audit_sandbox_denied(registry_path, repository, actor, task, reason) do
    AuditLog.record(registry_path, repository, %{
      "actor" => actor,
      "action" => "sandbox.run_denied",
      "target" => %{"type" => "task", "id" => task["key"]},
      "result" => "denied",
      "metadata" => %{
        "taskKey" => task["key"],
        "provider" => SandboxPolicy.provider(repository),
        "workspaceProvider" => "cloud_sandbox",
        "reasonCode" => reason
      }
    })

    :ok
  rescue
    _error -> :ok
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
