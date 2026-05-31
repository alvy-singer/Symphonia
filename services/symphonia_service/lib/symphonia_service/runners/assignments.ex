defmodule SymphoniaService.Runners.Assignments do
  @moduledoc """
  Remote runner assignment lifecycle and import orchestration.
  """

  alias SymphoniaService.Access.{Actor, AuditLog}

  alias SymphoniaService.CodingAssistant.{
    BranchManager,
    ContextPack,
    RunStore
  }

  alias SymphoniaService.Runners.{
    AssignmentStore,
    PatchBundle,
    PatchImporter,
    Registry,
    RemoteResult
  }

  alias SymphoniaService.{RepositoryRegistry, TaskStore, Workspace}

  def preflight(repository, task) do
    BranchManager.ensure_repo_ready_for_task_branch!(repository, task)
    :ok
  end

  def create_for_run(registry_path, repository, task, run, runner, actor, _params \\ %{}) do
    preflight(repository, task)

    base_branch = base_branch(repository)
    base_sha = current_head_sha!(repository["path"])
    head_branch = BranchManager.task_branch(task)

    context_pack = public_context_pack(repository, task, base_branch, head_branch)

    assignment =
      AssignmentStore.create(registry_path, %{
        "run_id" => run["id"],
        "repo_key" => repository["key"],
        "task_key" => task["key"],
        "runner_id" => runner["id"],
        "runner" => runner,
        "state" => "queued",
        "provider" => "codex_app_server",
        "base_branch" => base_branch,
        "base_sha" => base_sha,
        "repository" => repository_payload(repository, base_branch, base_sha),
        "context_pack" => context_pack
      })

    audit(registry_path, repository, actor, "runner.remote_run_selected", assignment, "completed")
    audit(registry_path, repository, actor, "runner.assignment_created", assignment, "completed")

    {:ok, assignment}
  end

  def create_sandbox_for_run(registry_path, repository, task, run, runner, actor, params \\ %{}) do
    preflight(repository, task)

    base_branch = base_branch(repository)
    base_sha = current_head_sha!(repository["path"])
    head_branch = BranchManager.task_branch(task)
    provider = sandbox_provider(params)

    assignment =
      AssignmentStore.create(registry_path, %{
        "run_id" => run["id"],
        "repo_key" => repository["key"],
        "task_key" => task["key"],
        "runner_id" => runner["id"],
        "runner_mode" => "cloud_sandbox",
        "runner" => runner,
        "state" => "queued",
        "provider" => provider,
        "workspace_provider" => "cloud_sandbox",
        "base_branch" => base_branch,
        "base_sha" => base_sha,
        "repository" => repository_payload(repository, base_branch, base_sha),
        "context_pack" =>
          sandbox_context_pack(repository, task, base_branch, head_branch, provider, params),
        "params" => sandbox_params(params)
      })
      |> finalize_sandbox_context(registry_path)

    audit(registry_path, repository, actor, "sandbox.run_selected", assignment, "completed",
      workspaceProvider: "cloud_sandbox"
    )

    audit(registry_path, repository, actor, "runner.assignment_created", assignment, "completed",
      workspaceProvider: "cloud_sandbox"
    )

    if provider == "gemini_cli" do
      audit(
        registry_path,
        repository,
        actor,
        "provider.gemini_cli_run_selected",
        assignment,
        "completed", workspaceProvider: "cloud_sandbox")
    end

    {:ok, assignment}
  end

  defp finalize_sandbox_context(%{"provider" => "gemini_cli"} = assignment, registry_path) do
    context =
      assignment["context_pack"]
      |> Map.put("assignmentId", assignment["id"])
      |> Map.put("runId", assignment["run_id"])
      |> Map.put("runnerId", assignment["runner_id"])
      |> Map.put("baseSha", assignment["base_sha"])

    {:ok, updated} =
      AssignmentStore.update(registry_path, assignment["id"], fn assignment ->
        {:ok, Map.put(assignment, "context_pack", context)}
      end)

    updated
  end

  defp finalize_sandbox_context(assignment, _registry_path), do: assignment

  def claim(registry_path, runner_id, token) do
    with {:ok, _runner} <- authenticate_runner(registry_path, runner_id),
         {:ok, _runner} <- Registry.authenticate(registry_path, runner_id, token) do
      case AssignmentStore.claim_next(registry_path, runner_id) do
        nil ->
          {:ok, nil}

        {:ok, assignment} ->
          with_run(registry_path, assignment, fn repository, _task, run ->
            run =
              run
              |> RunStore.mark_running()
              |> RunStore.mark_step("Claimed by runner")

            sync_task_run(repository, assignment["task_key"], run)
            :ok
          end)

          audit_for_assignment(
            registry_path,
            assignment,
            "runner.assignment_claimed",
            "completed"
          )

          {:ok, assignment}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def current(registry_path, runner_id, token) do
    with {:ok, _runner} <- Registry.authenticate(registry_path, runner_id, token) do
      {:ok, AssignmentStore.current_for_runner(registry_path, runner_id)}
    end
  end

  def record_event(registry_path, runner_id, assignment_id, token, payload) do
    with {:ok, _runner} <- Registry.authenticate(registry_path, runner_id, token),
         %{"runner_id" => ^runner_id} = assignment <-
           AssignmentStore.get(registry_path, assignment_id),
         :ok <- require_not_terminal(assignment),
         {:ok, _running_assignment} <- maybe_mark_running(registry_path, assignment),
         {:ok, assignment} <-
           AssignmentStore.append_public_event(
             registry_path,
             assignment_id,
             public_event(payload)
           ) do
      with_run(registry_path, assignment, fn repository, _task, run ->
        run = RunStore.mark_step(run, public_event(payload)["message"] || "Running on runner")
        sync_task_run(repository, assignment["task_key"], run)
        :ok
      end)

      {:ok, assignment}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def submit_result(registry_path, runner_id, assignment_id, token, result) do
    with {:ok, _runner} <- Registry.authenticate(registry_path, runner_id, token),
         %{"runner_id" => ^runner_id} = assignment <-
           AssignmentStore.get(registry_path, assignment_id),
         {:ok, patch} <- PatchBundle.validate(result, assignment),
         :ok <- require_result_allowed(assignment, patch["patch_digest"]) do
      case assignment["state"] do
        state when state in ["result_received", "importing", "completed"] ->
          {:ok, assignment, :idempotent}

        _state ->
          {:ok, assignment} = maybe_mark_running(registry_path, assignment)
          receive_and_import(registry_path, assignment, result, patch)
      end
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def submit_sandbox_result(registry_path, assignment_id, result, actor \\ Actor.default()) do
    with assignment when is_map(assignment) <- AssignmentStore.get(registry_path, assignment_id),
         {:ok, patch} <- PatchBundle.validate(result, assignment),
         :ok <- require_result_allowed(assignment, patch["patch_digest"]) do
      case assignment["state"] do
        state when state in ["result_received", "importing", "completed"] ->
          {:ok, assignment, :idempotent}

        _state ->
          {:ok, assignment} = maybe_mark_running(registry_path, assignment)
          receive_and_import(registry_path, assignment, result, patch, actor)
      end
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def fail_sandbox_assignment(registry_path, assignment_id, failure_class, public_message) do
    case AssignmentStore.get(registry_path, assignment_id) do
      nil ->
        {:error, :not_found}

      assignment ->
        if AssignmentStore.terminal?(assignment) do
          {:ok, assignment, :idempotent}
        else
          {:ok, failed} =
            AssignmentStore.transition(registry_path, assignment_id, "failed", %{
              "failure_class" => failure_class,
              "public_message" => public_message,
              "result_digest" =>
                RemoteResult.failure_digest(%{
                  "failureClass" => failure_class,
                  "publicMessage" => public_message
                })
            })

          fail_run_for_assignment(registry_path, failed, failure_class, public_message)
          audit_for_assignment(registry_path, failed, "runner.assignment_import_failed", "failed")
          {:ok, failed, :failed}
        end
    end
  end

  def fail(registry_path, runner_id, assignment_id, token, payload) do
    with {:ok, _runner} <- Registry.authenticate(registry_path, runner_id, token),
         %{"runner_id" => ^runner_id} = assignment <-
           AssignmentStore.get(registry_path, assignment_id),
         digest <- RemoteResult.failure_digest(payload),
         :ok <- require_fail_allowed(assignment, digest) do
      if assignment["state"] == "failed" do
        {:ok, assignment, :idempotent}
      else
        failure_class = payload["failureClass"] || payload["failure_class"] || "runner_failed"
        public_message = payload["publicMessage"] || payload["public_message"] || "Runner failed."

        {:ok, failed} =
          AssignmentStore.transition(registry_path, assignment_id, "failed", %{
            "failure_class" => failure_class,
            "public_message" => public_message,
            "result_digest" => digest
          })

        fail_run_for_assignment(registry_path, failed, failure_class, public_message)
        audit_for_assignment(registry_path, failed, "runner.assignment_import_failed", "failed")
        {:ok, failed, :failed}
      end
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def cancel_run(registry_path, repository, task_key, run) do
    assignment_id = run["assignment_id"]

    with id when is_binary(id) <- assignment_id,
         assignment when is_map(assignment) <- AssignmentStore.get(registry_path, id) do
      cancel_assignment(registry_path, assignment, repository, task_key, run)
    else
      _ -> {:error, "The run is no longer active."}
    end
  end

  def cancel_assignment(registry_path, assignment_id) when is_binary(assignment_id) do
    case AssignmentStore.get(registry_path, assignment_id) do
      nil -> {:error, :not_found}
      assignment -> cancel_assignment(registry_path, assignment)
    end
  end

  def cancel_assignment(registry_path, assignment) when is_map(assignment) do
    repository = RepositoryRegistry.get!(registry_path, assignment["repo_key"])
    task = TaskStore.get_task(repository, assignment["task_key"])
    run = RunStore.get(assignment["run_id"])
    cancel_assignment(registry_path, assignment, repository, task["key"], run)
  end

  defp cancel_assignment(registry_path, assignment, repository, task_key, run) do
    cond do
      AssignmentStore.terminal?(assignment) ->
        {:ok,
         %{"run" => RunStore.public(run), "task" => TaskStore.get_task(repository, task_key)}}

      assignment["state"] == "queued" ->
        {:ok, canceled} =
          AssignmentStore.transition(registry_path, assignment["id"], "canceled", %{
            "public_message" => "Remote assignment canceled before it was claimed.",
            "cancellation_requested" => true
          })

        canceled_run = RunStore.mark_canceled(run)

        task =
          repository
          |> TaskStore.apply_event(task_key, "pause_run", %{
            "explanation" => "Run canceled. The task is paused. You can retry when ready."
          })
          |> then(fn _task -> sync_task_run(repository, task_key, canceled_run) end)

        audit_for_assignment(registry_path, canceled, "runner.assignment_canceled", "completed")
        {:ok, %{"run" => RunStore.public(canceled_run), "task" => task}}

      true ->
        {:ok, canceled} =
          AssignmentStore.transition(registry_path, assignment["id"], "canceled", %{
            "public_message" => "Remote assignment cancellation was requested.",
            "cancellation_requested" => true
          })

        canceled_run = RunStore.mark_canceled(run)

        task =
          repository
          |> TaskStore.apply_event(task_key, "pause_run", %{
            "explanation" => "Run canceled. The task is paused. You can retry when ready."
          })
          |> then(fn _task -> sync_task_run(repository, task_key, canceled_run) end)

        audit_for_assignment(registry_path, canceled, "runner.assignment_canceled", "completed")
        {:ok, %{"run" => RunStore.public(canceled_run), "task" => task}}
    end
  end

  def runner_response(nil), do: %{"assignment" => nil}

  def runner_response(assignment),
    do: %{"assignment" => AssignmentStore.runner_payload(assignment)}

  def public_response(nil), do: %{"assignment" => nil}
  def public_response(assignment), do: %{"assignment" => AssignmentStore.public(assignment)}

  defp receive_and_import(registry_path, assignment, result, patch, _actor \\ Actor.default()) do
    {:ok, received} =
      AssignmentStore.transition(registry_path, assignment["id"], "result_received", %{
        "result_digest" => patch["patch_digest"],
        "changed_files_digest" => patch["changed_files_digest"],
        "changed_files" => patch["changed_files"],
        "public_timeline" => RemoteResult.public_timeline(result),
        "public_message" => RemoteResult.public_summary(result)
      })

    audit_for_assignment(
      registry_path,
      received,
      "runner.assignment_result_received",
      "completed",
      changedFileCount: patch["changed_file_count"]
    )

    {:ok, importing} =
      AssignmentStore.transition(registry_path, assignment["id"], "importing", %{
        "public_message" => "Symphonia is importing the returned patch."
      })

    audit_for_assignment(
      registry_path,
      importing,
      "runner.assignment_import_started",
      "completed",
      changedFileCount: patch["changed_file_count"]
    )

    with_run(registry_path, importing, fn repository, task, run ->
      run = RunStore.mark_step(run, "Receiving remote result")
      sync_task_run(repository, task["key"], run)

      case PatchImporter.import(registry_path, repository, task, run, importing, result) do
        {:ok, import_result} ->
          completed_run = import_result["run"]

          {:ok, completed} =
            AssignmentStore.transition(registry_path, assignment["id"], "completed", %{
              "public_message" =>
                "Runner returned a patch. Symphonia imported it locally and ran validation before creating the handoff."
            })

          audit_for_assignment(
            registry_path,
            completed,
            "runner.assignment_import_completed",
            "completed",
            changedFileCount: patch["changed_file_count"]
          )

          {:ok, completed, completed_run, import_result["task"]}

        {:error, reason} ->
          failure_class = to_string(reason)

          {:ok, failed} =
            AssignmentStore.transition(registry_path, assignment["id"], "failed", %{
              "failure_class" => failure_class,
              "public_message" => public_import_failure(failure_class)
            })

          fail_run_for_assignment(
            registry_path,
            failed,
            failure_class,
            public_import_failure(failure_class)
          )

          audit_for_assignment(
            registry_path,
            failed,
            "runner.assignment_import_failed",
            "failed",
            reasonCode: failure_class,
            changedFileCount: patch["changed_file_count"]
          )

          {:error, failure_class}
      end
    end)
    |> case do
      {:ok, completed, _run, _task} -> {:ok, completed, :imported}
      {:error, reason} -> {:error, reason}
      other -> other
    end
  end

  defp fail_run_for_assignment(registry_path, assignment, failure_class, public_message) do
    with_run(registry_path, assignment, fn repository, task, run ->
      failed_run =
        run
        |> RunStore.mark_failed(failure_class, public_message)
        |> RunStore.update_metadata(%{"failure_class" => failure_class})

      repository
      |> TaskStore.apply_event(task["key"], "fail_run", %{
        "explanation" => public_message,
        "paused_reason" => "run_failed"
      })
      |> then(fn _task -> sync_task_run(repository, task["key"], failed_run) end)

      :ok
    end)
  end

  defp require_result_allowed(%{"state" => "canceled"}, _digest),
    do: {:error, "assignment_canceled"}

  defp require_result_allowed(%{"state" => "failed"}, _digest),
    do: {:error, "assignment_already_finalized"}

  defp require_result_allowed(%{"state" => state} = assignment, digest)
       when state in ["result_received", "importing", "completed"] do
    if AssignmentStore.same_result?(assignment, digest) do
      :ok
    else
      {:error, "assignment_already_finalized"}
    end
  end

  defp require_result_allowed(_assignment, _digest), do: :ok

  defp require_fail_allowed(%{"state" => "completed"}, _digest),
    do: {:error, "assignment_already_finalized"}

  defp require_fail_allowed(%{"state" => "canceled"}, _digest),
    do: {:error, "assignment_canceled"}

  defp require_fail_allowed(%{"state" => "failed"} = assignment, digest) do
    if AssignmentStore.same_result?(assignment, digest) do
      :ok
    else
      {:error, "assignment_already_finalized"}
    end
  end

  defp require_fail_allowed(_assignment, _digest), do: :ok

  defp require_not_terminal(assignment) do
    if AssignmentStore.terminal?(assignment), do: {:error, :assignment_finalized}, else: :ok
  end

  defp maybe_mark_running(registry_path, %{"state" => "claimed"} = assignment) do
    AssignmentStore.transition(registry_path, assignment["id"], "running", %{
      "public_message" => "Runner is working on the assignment."
    })
  end

  defp maybe_mark_running(_registry_path, assignment), do: {:ok, assignment}

  defp authenticate_runner(registry_path, runner_id) do
    case Registry.get(registry_path, runner_id) do
      {:ok, %{"status" => "online"} = runner} -> {:ok, runner}
      {:ok, %{"status" => "disabled"}} -> {:error, :runner_disabled}
      {:ok, %{"status" => "stale"}} -> {:error, :runner_stale}
      {:ok, %{"status" => "offline"}} -> {:error, :runner_offline}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :runner_unavailable}
    end
  end

  defp with_run(registry_path, assignment, fun) when is_function(fun, 3) do
    repository = RepositoryRegistry.get!(registry_path, assignment["repo_key"])
    task = TaskStore.get_task(repository, assignment["task_key"])
    run = RunStore.get(assignment["run_id"])

    cond do
      is_nil(task) -> {:error, :task_not_found}
      is_nil(run) -> {:error, :run_not_found}
      true -> fun.(repository, task, run)
    end
  end

  defp sync_task_run(repository, task_key, run) do
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
      "message" => SymphoniaService.CodingAssistant.RunEvents.public_message(run),
      "display_step" => SymphoniaService.CodingAssistant.RunEvents.display_step(run),
      "display_message" => SymphoniaService.CodingAssistant.RunEvents.display_message(run),
      "eligibility_reason" => run["eligibility_reason"],
      "runner" => run["runner"],
      "execution_mode" => run["execution_mode"],
      "assignment_id" => run["assignment_id"],
      "workspace_provider" => run["workspace_provider"],
      "review_branch" => run["review_branch"],
      "curated_summary_path" => run["curated_summary_path"],
      "cleanup_warning" => run["cleanup_warning"],
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

  defp sandbox_params(params) when is_map(params) do
    params
    |> Map.take([
      "fakeSandboxFailure",
      "fake_sandbox_failure",
      "fakeSandboxEventsPath",
      "fake_sandbox_events_path",
      "fakePatchPath",
      "fake_patch_path",
      "fakePatchBody",
      "fake_patch_body"
    ])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp sandbox_params(_params), do: %{}

  defp public_context_pack(repository, task, base_branch, head_branch) do
    context = %{
      base_branch: base_branch,
      head_branch: head_branch,
      repo_path: "runner-managed checkout",
      persistent: false,
      workspace_provider: "remote_patch_bundle"
    }

    brief =
      task
      |> Map.get("body", "")
      |> String.trim()
      |> String.slice(0, 20_000)

    prompt =
      """
      You are the Coding Assistant working in a runner-managed checkout.

      Task key: #{task["key"]}
      Task title: #{task["title"]}
      Repository: #{repository["name"] || repository["key"]}
      Base branch: #{base_branch}
      Head branch: #{head_branch}

      Task brief:
      #{brief}

      WORKFLOW.md:
      #{Workspace.workflow(repository)["body"] || "No WORKFLOW.md found."}

      Rules:
      - Make the code changes needed for the task in this checkout.
      - Do not commit, push, or open a pull request.
      - Return a git diff patch bundle to Symphonia.
      - Do not edit symphonia/tasks, symphonia/run-summaries, WORKFLOW.md, .symphonia, or registry files.
      """
      |> String.trim()
      |> Kernel.<>("\n")

    %{
      "publicTaskBrief" => brief,
      "renderedPrompt" => prompt,
      "constraints" => [
        "Do not commit.",
        "Do not push.",
        "Do not edit Symphonia metadata."
      ],
      "context" =>
        Map.drop(ContextPack.build(repository, task, context), ["existingCodexThreadId"])
    }
  end

  defp sandbox_context_pack(repository, task, base_branch, head_branch, "gemini_cli", params) do
    context = %{
      base_branch: base_branch,
      head_branch: head_branch,
      repo_path: "sandbox source-bundle workspace",
      persistent: false,
      workspace_provider: "cloud_sandbox"
    }

    ContextPack.provider_context(repository, task, context, params, provider: :gemini_cli)
  end

  defp sandbox_context_pack(repository, task, base_branch, head_branch, _provider, _params) do
    public_context_pack(repository, task, base_branch, head_branch)
  end

  defp sandbox_provider(params) do
    case params["providerId"] || params["provider_id"] || "codex_app_server" do
      "gemini_cli" -> "gemini_cli"
      _other -> "codex_app_server"
    end
  end

  defp repository_payload(repository, base_branch, base_sha) do
    %{
      "repoKey" => repository["key"],
      "remoteUrl" => safe_remote_url(repository),
      "baseBranch" => base_branch,
      "baseSha" => base_sha,
      "credentialMode" => "runner_managed"
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp safe_remote_url(repository) do
    remote_url =
      get_in(repository, ["github", "clone_url"]) || get_in(repository, ["github", "cloneUrl"])

    cond do
      not is_binary(remote_url) -> nil
      String.contains?(remote_url, "@") and String.starts_with?(remote_url, "https://") -> nil
      String.contains?(remote_url, "token") -> nil
      String.starts_with?(remote_url, "/") -> nil
      true -> remote_url
    end
  end

  defp base_branch(repository) do
    get_in(repository, ["github", "default_branch"]) ||
      get_in(repository, ["github", "defaultBranch"]) ||
      "main"
  end

  defp current_head_sha!(repo_path) do
    case System.cmd("git", ["-C", repo_path, "rev-parse", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      {output, _status} -> raise ArgumentError, String.trim(output)
    end
  end

  defp public_event(payload) when is_map(payload) do
    %{
      "step" => payload["step"] || "running_on_runner",
      "message" => payload["message"] || "Running on runner"
    }
  end

  defp public_event(_payload),
    do: %{"step" => "running_on_runner", "message" => "Running on runner"}

  defp public_import_failure("import_in_progress"),
    do: "Symphonia is already importing this assignment."

  defp public_import_failure(_reason), do: "Symphonia could not import the returned patch."

  defp audit_for_assignment(registry_path, assignment, action, result, extra \\ []) do
    repository = RepositoryRegistry.get!(registry_path, assignment["repo_key"])
    audit(registry_path, repository, Actor.default(), action, assignment, result, extra)
  rescue
    _error -> :ok
  end

  defp audit(registry_path, repository, actor, action, assignment, result, extra \\ []) do
    metadata =
      %{
        "runnerId" => assignment["runner_id"],
        "runnerMode" => assignment["runner_mode"] || "remote_runner",
        "assignmentId" => assignment["id"],
        "runId" => assignment["run_id"],
        "taskKey" => assignment["task_key"],
        "provider" => assignment["provider"],
        "workspaceProvider" => extra[:workspaceProvider] || assignment["workspace_provider"],
        "reasonCode" => extra[:reasonCode] || assignment["failure_class"],
        "changedFileCount" => extra[:changedFileCount]
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    AuditLog.record(registry_path, repository, %{
      "actor" => actor,
      "action" => action,
      "target" => %{"type" => "runner", "id" => assignment["runner_id"]},
      "result" => result,
      "metadata" => metadata
    })
  rescue
    _error -> :ok
  end
end
