defmodule SymphoniaService.Runner.CloudSandboxProvider do
  @moduledoc """
  Assignment-backed cloud sandbox execution bridge.

  This module runs sandbox lifecycle work behind Symphonia's existing
  assignment/result/import contract. Sandbox providers produce patches; Symphonia
  imports and validates those patches locally.
  """

  alias SymphoniaService.Access.{Actor, AuditLog}
  alias SymphoniaService.CodingAssistant.RunStore
  alias SymphoniaService.Runners.{AssignmentStore, Assignments}

  alias SymphoniaService.Sandbox.{
    OpenSandboxOperations,
    OpenSandboxProvider,
    Policy,
    Registry,
    Session
  }

  alias SymphoniaService.TaskStore

  def runner_metadata(repository), do: Policy.runner_metadata(repository)

  def start(registry_path, repository, task, run, assignment, actor, params \\ %{}) do
    Task.start(fn ->
      execute(registry_path, repository, task, run, assignment, actor || Actor.default(), params)
    end)
  end

  def execute(registry_path, repository, task, run, assignment, actor, params \\ %{}) do
    with {:ok, provider} <- Registry.resolve(repository) do
      execute_with_provider(
        registry_path,
        repository,
        task,
        run,
        assignment,
        actor,
        params,
        provider
      )
    else
      {:error, reason} ->
        fail_assignment(registry_path, repository, task, assignment, reason, :ok)
    end
  end

  defp execute_with_provider(
         registry_path,
         repository,
         task,
         run,
         assignment,
         actor,
         params,
         provider
       ) do
    try do
      run = mark(registry_path, repository, task, run, "Creating sandbox")
      audit(registry_path, repository, actor, "sandbox.create_started", assignment, "completed")

      create_opts =
        params
        |> Map.put("assignment", assignment)
        |> Map.put("registry_path", registry_path)
        |> Map.put("repository", repository)

      case provider.create(create_opts) do
        {:ok, session} ->
          audit(
            registry_path,
            repository,
            actor,
            "sandbox.create_completed",
            assignment,
            "completed"
          )

          run = mark(registry_path, repository, task, run, "Preparing sandbox workspace")

          audit(
            registry_path,
            repository,
            actor,
            "sandbox.prepare_started",
            assignment,
            "completed"
          )

          with {:ok, claimed} <- claim_assignment(registry_path, assignment),
               {:ok, context} <-
                 provider.prepare(session, repository, Map.put(claimed, "params", params)) do
            audit(
              registry_path,
              repository,
              actor,
              "sandbox.prepare_completed",
              claimed,
              "completed"
            )

            execute_prepared(
              registry_path,
              repository,
              task,
              run,
              claimed,
              actor,
              params,
              provider,
              context
            )
          else
            {:error, reason} ->
              release_result =
                release(provider, session, registry_path, repository, actor, assignment)

              fail_assignment(registry_path, repository, task, assignment, reason, release_result)
          end

        {:error, reason} ->
          fail_assignment(registry_path, repository, task, assignment, reason, :ok)
      end
    rescue
      error ->
        fail_assignment(
          registry_path,
          repository,
          task,
          assignment,
          Exception.message(error),
          :ok
        )
    end
  end

  defp execute_prepared(
         registry_path,
         repository,
         task,
         run,
         claimed,
         actor,
         params,
         provider,
         context
       ) do
    run = mark(registry_path, repository, task, run, running_step(claimed))
    audit(registry_path, repository, actor, "sandbox.run_started", claimed, "completed")

    with {:ok, running} <- mark_assignment_running(registry_path, claimed),
         {:ok, result} <-
           provider.run(
             Session.mark(context, "running"),
             context,
             Map.put(running, "params", params)
           ) do
      mark(registry_path, repository, task, run, "Receiving sandbox changes")

      case Assignments.submit_sandbox_result(registry_path, running["id"], result, actor) do
        {:ok, completed, _mode} ->
          audit(
            registry_path,
            repository,
            actor,
            "sandbox.result_received",
            completed,
            "completed",
            changedFileCount: length(List.wrap(completed["changed_files"]))
          )

          audit_provider_result(registry_path, repository, actor, completed)

          mark_latest(repository, task, completed, "Releasing sandbox")
          release_result = release(provider, context, registry_path, repository, actor, completed)
          mark_release_result(repository, task, completed, release_result)
          apply_release_warning(release_result, registry_path, repository, task, completed)

        {:error, reason} ->
          release_result = release(provider, context, registry_path, repository, actor, running)
          fail_assignment(registry_path, repository, task, running, reason, release_result)
      end
    else
      {:error, reason} ->
        release_result = release(provider, context, registry_path, repository, actor, claimed)
        fail_assignment(registry_path, repository, task, claimed, reason, release_result)
    end
  end

  defp claim_assignment(registry_path, assignment) do
    AssignmentStore.transition(registry_path, assignment["id"], "claimed", %{
      "claimed_at" => now(),
      "public_message" => "Sandbox session claimed the assignment."
    })
  end

  defp mark_assignment_running(registry_path, assignment) do
    AssignmentStore.transition(registry_path, assignment["id"], "running", %{
      "public_message" => "Sandbox is working on the assignment."
    })
  end

  defp release(provider, session, registry_path, repository, actor, assignment) do
    audit(registry_path, repository, actor, "sandbox.release_started", assignment, "completed")

    case provider.release(session) do
      :ok ->
        record_opensandbox_cleanup(provider, registry_path, repository, :ok)

        audit(
          registry_path,
          repository,
          actor,
          "sandbox.release_completed",
          assignment,
          "completed"
        )

        :ok

      {:error, reason} ->
        record_opensandbox_cleanup(provider, registry_path, repository, {:error, reason})

        audit(registry_path, repository, actor, "sandbox.release_failed", assignment, "failed",
          reasonCode: "sandbox_release_failed"
        )

        {:error, reason}
    end
  end

  defp apply_release_warning(:ok, _registry_path, _repository, _task, _assignment), do: :ok

  defp apply_release_warning({:error, _reason}, registry_path, repository, task, assignment) do
    run =
      assignment["run_id"]
      |> RunStore.get()
      |> RunStore.update_metadata(%{"cleanup_warning" => Session.cleanup_warning()})

    sync_task_run(repository, task["key"], run)

    AssignmentStore.update(registry_path, assignment["id"], fn assignment ->
      {:ok, Map.put(assignment, "cleanup_warning", Session.cleanup_warning())}
    end)

    :ok
  end

  defp record_opensandbox_cleanup(OpenSandboxProvider, registry_path, repository, result) do
    OpenSandboxOperations.record_cleanup(registry_path, repository, result)
    :ok
  rescue
    _error -> :ok
  end

  defp record_opensandbox_cleanup(_provider, _registry_path, _repository, _result), do: :ok

  defp fail_assignment(registry_path, repository, task, assignment, reason, release_result) do
    failure_class = safe_reason(reason)
    public_message = "Sandbox execution could not produce a reviewable patch."

    Assignments.fail_sandbox_assignment(
      registry_path,
      assignment["id"],
      failure_class,
      public_message
    )

    audit_provider_failed(registry_path, repository, Actor.default(), assignment, failure_class)

    case release_result do
      {:error, _release_reason} ->
        run =
          assignment["run_id"]
          |> RunStore.get()
          |> RunStore.update_metadata(%{"cleanup_warning" => Session.cleanup_warning()})

        sync_task_run(repository, task["key"], run)

      _other ->
        :ok
    end

    :ok
  end

  defp running_step(%{"provider" => "gemini_cli"}), do: "Running Gemini in sandbox"
  defp running_step(_assignment), do: "Running Codex in sandbox"

  defp audit_provider_result(
         registry_path,
         repository,
         actor,
         %{"provider" => "gemini_cli"} = assignment
       ) do
    audit(
      registry_path,
      repository,
      actor,
      "provider.gemini_cli_result_received",
      assignment,
      "completed",
      changedFileCount: length(List.wrap(assignment["changed_files"]))
    )
  end

  defp audit_provider_result(_registry_path, _repository, _actor, _assignment), do: :ok

  defp audit_provider_failed(
         registry_path,
         repository,
         actor,
         %{"provider" => "gemini_cli"} = assignment,
         reason
       ) do
    audit(
      registry_path,
      repository,
      actor,
      "provider.gemini_cli_run_failed",
      assignment,
      "failed",
      reasonCode: reason
    )
  end

  defp audit_provider_failed(_registry_path, _repository, _actor, _assignment, _reason), do: :ok

  defp mark(_registry_path, repository, task, run, step) do
    run = RunStore.mark_step(run, step)
    sync_task_run(repository, task["key"], run)
    run
  end

  defp mark_latest(repository, task, assignment, step) do
    assignment["run_id"]
    |> RunStore.get()
    |> RunStore.mark_step(step)
    |> tap(&sync_task_run(repository, task["key"], &1))
  end

  defp mark_release_result(repository, task, assignment, :ok),
    do: mark_latest(repository, task, assignment, "Sandbox released")

  defp mark_release_result(repository, task, assignment, {:error, _reason}),
    do: mark_latest(repository, task, assignment, "Sandbox cleanup needs attention")

  defp sync_task_run(repository, task_key, run) do
    TaskStore.patch_task(repository, task_key, %{
      "frontmatter" => %{
        "assistant" => run["provider"] || "coding_assistant",
        "run" =>
          %{
            "id" => run["id"],
            "kind" => run["kind"],
            "state" => run["state"],
            "provider" => run["provider"],
            "current_step" => run["current_step"],
            "message" => SymphoniaService.CodingAssistant.RunEvents.public_message(run),
            "display_step" => SymphoniaService.CodingAssistant.RunEvents.display_step(run),
            "display_message" => SymphoniaService.CodingAssistant.RunEvents.display_message(run),
            "eligibility_reason" => run["eligibility_reason"],
            "runner" => run["runner"],
            "execution_mode" => run["execution_mode"],
            "assignment_id" => run["assignment_id"],
            "workspace_provider" => run["workspace_provider"],
            "review_branch" => run["review_branch"],
            "curated_summary_id" => run["curated_summary_id"],
            "curated_summary_path" => run["curated_summary_path"],
            "evidence_ids" => run["evidence_ids"],
            "cleanup_warning" => run["cleanup_warning"],
            "failure_class" => run["failure_class"],
            "started_at" => run["started_at"],
            "completed_at" => run["completed_at"]
          }
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()
      }
    })
  end

  defp audit(registry_path, repository, actor, action, assignment, result, extra \\ []) do
    metadata =
      %{
        "runId" => assignment["run_id"],
        "taskKey" => assignment["task_key"],
        "provider" => assignment["provider"],
        "workspaceProvider" => "cloud_sandbox",
        "reasonCode" => extra[:reasonCode],
        "changedFileCount" => extra[:changedFileCount]
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    AuditLog.record(registry_path, repository, %{
      "actor" => actor,
      "action" => action,
      "target" => %{"type" => "runner", "id" => "cloud_sandbox"},
      "result" => result,
      "metadata" => metadata
    })

    :ok
  rescue
    _error -> :ok
  end

  defp safe_reason(reason) do
    reason
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9._-]/, "_")
    |> String.slice(0, 80)
    |> case do
      "" -> "sandbox_failed"
      value -> value
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
