defmodule SymphoniaService.Runners.PatchImporter do
  @moduledoc """
  Imports validated remote runner patch bundles into the local review workspace.
  """

  alias SymphoniaService.CodingAssistant.{
    BranchManager,
    ChangeDetector,
    CuratedSummary,
    HandoffBuilder,
    RunStore
  }

  alias SymphoniaService.PrivateWorkspace
  alias SymphoniaService.Runners.{ImportLock, PatchBundle, RemoteResult}
  alias SymphoniaService.Validation.{Evidence, Policy, Runner}

  def import(registry_path, repository, task, run, assignment, result) do
    repository = private_repository(repository, registry_path)

    ImportLock.with_lock(run["id"], fn ->
      with {:ok, patch} <- PatchBundle.validate(result, assignment) do
        do_import(repository, task, run, assignment, result, patch)
      end
    end)
  end

  def import_locked?(run_id), do: ImportLock.active?(run_id)

  defp do_import(repository, task, run, assignment, result, patch) do
    context = BranchManager.prepare_persistent_task_branch_worktree!(repository, task)

    try do
      run =
        run
        |> RunStore.update_metadata(%{
          "workspace_path" => context.repo_path,
          "workspace_provider" => import_workspace_provider(run),
          "review_branch" => context.head_branch
        })
        |> RunStore.mark_step("Importing returned patch")

      with :ok <- verify_base_sha(context.repo_path, assignment["base_sha"]),
           :ok <- apply_patch(context.repo_path, assignment["id"], patch["diff"]),
           :ok <- reject_symlink_outputs(context.repo_path, patch["changed_files"]),
           {:ok, changes} <- reviewable_changes(run, context.repo_path),
           :ok <- ensure_committable_changes(changes),
           {:ok, validation} <- run_validation(repository, run, context.repo_path, task),
           {:ok, summary} <-
             write_summary(
               repository,
               run,
               task,
               changes,
               result,
               validation["public_evidence"]
             ),
           :ok <- commit_and_push(run, context, task, changes) do
        files_changed = Enum.sort(changes["committable"])

        handoff =
          HandoffBuilder.build_from_changes(
            task,
            context,
            files_changed,
            RemoteResult.public_summary(result),
            validation["public_evidence"]
          )
          |> Map.put("head_branch", context.head_branch)
          |> Map.put("base_branch", context.base_branch)
          |> Map.put("curated_summary_id", summary["id"])
          |> Map.put("curated_summary_path", private_summary_ref(summary))
          |> Map.put("evidence_ids", validation["evidence_ids"])
          |> maybe_failed_validation_next_action(validation["results"])

        completed_run =
          run
          |> RunStore.mark_step("Writing handoff")
          |> RunStore.mark_completed(handoff)

        task = HandoffBuilder.apply(repository, task["key"], completed_run, handoff)

        {:ok,
         %{
           "run" => completed_run,
           "task" => task,
           "handoff" => handoff,
           "changed_files" => files_changed,
           "patch" => patch
         }}
      end
    after
      BranchManager.release_persistent_task_branch_worktree(context)
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp verify_base_sha(repo_path, expected_sha) do
    case git(repo_path, ["rev-parse", "HEAD"]) do
      {:ok, ^expected_sha} -> :ok
      {:ok, _actual} -> {:error, "base_sha_mismatch"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp import_workspace_provider(%{"execution_mode" => "cloud_sandbox"}), do: "cloud_sandbox"
  defp import_workspace_provider(%{"workspace_provider" => "cloud_sandbox"}), do: "cloud_sandbox"
  defp import_workspace_provider(_run), do: "local_git_worktree"

  defp apply_patch(repo_path, assignment_id, diff) do
    patch_path = temp_patch_path(assignment_id)
    File.write!(patch_path, diff)

    try do
      with {:ok, _output} <- git(repo_path, ["apply", "--check", patch_path]),
           {:ok, _output} <- git(repo_path, ["apply", patch_path]) do
        :ok
      end
    after
      File.rm(patch_path)
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp reviewable_changes(run, repo_path) do
    run = RunStore.mark_step(run, "Checking imported changes")
    changes = ChangeDetector.detect!(repo_path)

    if changes["excluded"] != [] do
      BranchManager.revert_paths!(repo_path, changes["excluded"])
      {:error, "protected_path_rejected"}
    else
      RunStore.record_provider_output(run, %{"remote_change_detection" => changes})
      {:ok, changes}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp ensure_committable_changes(%{"committable" => []}), do: {:error, "no_reviewable_files"}
  defp ensure_committable_changes(_changes), do: :ok

  defp run_validation(repository, run, repo_path, task) do
    RunStore.mark_step(run, "Validating imported changes")

    policy = Policy.load(repo_path, task)
    {:ok, results} = Runner.run(repo_path, policy)
    public_evidence = Evidence.public(results)

    evidence_records =
      PrivateWorkspace.record_validation_evidence(repository, run, public_evidence)

    evidence_ids = Enum.map(evidence_records, & &1["id"])
    RunStore.update_metadata(run, %{"evidence_ids" => evidence_ids})

    RunStore.record_provider_output(run, %{
      "validation" => %{"policy" => policy, "results" => results}
    })

    {:ok,
     %{
       "policy" => policy,
       "results" => results,
       "public_evidence" => public_evidence,
       "evidence_ids" => evidence_ids
     }}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp write_summary(repository, run, task, changes, result, validation_evidence) do
    summary =
      CuratedSummary.write_private!(
        repository,
        task,
        RunStore.get(run["id"]) || run,
        changes["committable"],
        RemoteResult.public_summary(result),
        validation_evidence
      )

    RunStore.update_metadata(run, %{
      "curated_summary_id" => summary["id"],
      "curated_summary_path" => private_summary_ref(summary)
    })

    {:ok, summary}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp commit_and_push(run, context, task, changes) do
    RunStore.mark_step(run, "Creating review branch")

    BranchManager.commit_files!(
      context,
      task,
      Enum.sort(changes["committable"])
    )

    BranchManager.push_task_branch!(context)
    :ok
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp private_summary_ref(summary), do: "private-workspace/run_summary/#{summary["id"]}"

  defp private_repository(repository, registry_path) when is_binary(registry_path) do
    Map.put(repository, "_registry_path", registry_path)
  end

  defp private_repository(repository, _registry_path), do: repository

  defp maybe_failed_validation_next_action(handoff, results) do
    if Evidence.has_failed_required?(results) do
      Map.put(
        handoff,
        "next_review_action",
        "Review the failed validation before approving. Request changes if Codex should fix it."
      )
    else
      handoff
    end
  end

  defp reject_symlink_outputs(repo_path, paths) do
    Enum.reduce_while(paths, :ok, fn path, :ok ->
      full_path = Path.expand(path, repo_path)

      cond do
        not String.starts_with?(full_path, Path.expand(repo_path) <> "/") ->
          {:halt, {:error, "path_traversal_rejected"}}

        symlink_path?(full_path) ->
          {:halt, {:error, "symlink_patch_rejected"}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp symlink_path?(path) do
    case File.lstat(path) do
      {:ok, %{type: :symlink}} -> true
      _other -> false
    end
  end

  defp git(repo_path, args) do
    case System.cmd("git", ["-C", repo_path | args], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, _status} -> {:error, clean_git_error(output)}
    end
  end

  defp clean_git_error(output) do
    output
    |> to_string()
    |> String.trim()
    |> case do
      "" -> "git_command_failed"
      message -> message
    end
  end

  defp temp_patch_path(assignment_id) do
    safe =
      assignment_id
      |> to_string()
      |> String.replace(~r/[^a-zA-Z0-9._-]/, "-")
      |> String.trim("-")

    Path.join(System.tmp_dir!(), "#{safe}.patch")
  end
end
