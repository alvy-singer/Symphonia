defmodule SymphoniaService.CodingAssistant.AppServerProvider do
  @moduledoc """
  Coding Assistant provider backed by Codex App Server.
  """

  @behaviour SymphoniaService.CodingAssistant.Provider

  alias SymphoniaService.{PrivateWorkspace, TaskStore}

  alias SymphoniaService.CodingAssistant.{
    AppServerClient,
    BranchManager,
    ChangeDetector,
    ContextPack,
    CuratedSummary,
    FailureClass,
    HandoffBuilder,
    RunEvents,
    RunStore
  }

  alias SymphoniaService.Runner.{ChangeApplier, WorkspaceProviders}
  alias SymphoniaService.Validation.{Evidence, Policy, Runner}

  @impl true
  def id, do: "codex_app_server"

  @impl true
  def label, do: "Codex App Server"

  @impl true
  def capabilities do
    %{
      "context_pack" => true,
      "persistent_workspace" => true,
      "streamed_public_steps" => true,
      "change_detection" => true,
      "validation_pipeline" => true,
      "curated_summary" => true,
      "review_branch" => true,
      "handoff" => true,
      "retry_classification" => true
    }
  end

  @impl true
  def readiness(opts \\ []) do
    readiness = AppServerClient.check_ready(opts)

    %{
      "configured" => readiness["configured"],
      "ready" => readiness["ready"],
      "schemaAvailable" => readiness["schemaAvailable"],
      "binaryAvailable" => readiness["binaryAvailable"],
      "daemonReachable" => readiness["daemonReachable"],
      "reason" => readiness["reason"]
    }
  end

  @impl true
  def preflight(repository, task, params) do
    with :ok <- AppServerClient.ensure_schema_bundle!(),
         :ok <- AppServerClient.ensure_daemon_ready!(app_server_opts(%{}, params)),
         :ok <- branch_preflight(repository, task) do
      :ok
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  @impl true
  def run(repository, task, run, params) do
    if force_failure?(params) do
      {:error, "The Coding Assistant could not produce a reviewable handoff."}
    else
      with :ok <- AppServerClient.ensure_schema_bundle!(),
           :ok <- AppServerClient.ensure_daemon_ready!(app_server_opts(run, params)),
           :ok <- branch_preflight(repository, task) do
        with {:ok, context} <- WorkspaceProviders.prepare(repository, task, run, params) do
          review_context = WorkspaceProviders.review_context(context)
          record_workspace_metadata(run, context, review_context)

          try do
            prompt =
              ContextPack.render_prompt(repository, task, context, params, mode: :app_server)

            with {:ok, output} <-
                   invoke_app_server(repository, task["key"], run, context.repo_path, prompt),
                 {:ok, changes} <- reviewable_changes(run, context, review_context),
                 :ok <- ensure_committable_changes(changes),
                 {:ok, validation} <-
                   run_validation(repository, run, review_context.repo_path, task),
                 {:ok, summary} <-
                   write_summary(
                     repository,
                     run,
                     task,
                     changes,
                     output,
                     validation["public_evidence"]
                   ),
                 :ok <- commit_and_push(run, review_context, task, changes) do
              files_changed = Enum.sort(changes["committable"])

              handoff =
                HandoffBuilder.build_from_changes(
                  task,
                  review_context,
                  files_changed,
                  output["last_message"],
                  validation["public_evidence"]
                )
                |> Map.put("head_branch", review_context.head_branch)
                |> Map.put("base_branch", review_context.base_branch)
                |> Map.put("curated_summary_id", summary["id"])
                |> Map.put("curated_summary_path", private_summary_ref(summary))
                |> Map.put("evidence_ids", validation["evidence_ids"])
                |> maybe_failed_validation_next_action(validation["results"])

              {:ok, handoff}
            else
              {:error, reason} -> {:error, reason}
            end
          after
            WorkspaceProviders.release(context, run)
          end
        end
      end
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  @impl true
  def classify_failure(reason, context), do: FailureClass.classify(reason, context)

  defp branch_preflight(repository, task) do
    BranchManager.ensure_repo_ready_for_task_branch!(repository, task)
    :ok
  end

  defp record_workspace_metadata(run, context, review_context) do
    RunStore.update_metadata(run, %{
      "workspace_path" => context.repo_path,
      "workspace_provider" => context.workspace_provider || "local_git_worktree",
      "review_branch" => review_context.head_branch
    })

    if context.workspace_provider == "experimental_sandbox" do
      RunStore.record_provider_output(run, %{
        "workspace" => %{
          "workspace_provider" => "experimental_sandbox",
          "sandbox" => private_workspace_metadata(context)
        }
      })
    end

    :ok
  end

  defp private_workspace_metadata(context) do
    private = Map.get(context, :private, %{})

    %{
      "sandbox_id" => private[:sandbox_id],
      "sandbox_path" => private[:sandbox_path],
      "sandbox_events_path" => private[:sandbox_events_path]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp invoke_app_server(repository, task_key, run, repo_path, prompt) do
    opts =
      run
      |> app_server_opts(%{})
      |> Keyword.put(:on_step, &mark_run_step(repository, task_key, run, &1))
      |> Keyword.put(
        :on_thread_id,
        &update_run_metadata(repository, task_key, run, %{"codex_thread_id" => &1})
      )
      |> Keyword.put(
        :on_turn_id,
        &update_run_metadata(repository, task_key, run, %{"turn_id" => &1})
      )

    case AppServerClient.run_turn(repo_path, prompt, opts) do
      {:ok, output} ->
        RunStore.update_metadata(run, %{
          "codex_thread_id" => output["thread_id"],
          "turn_id" => output["turn_id"]
        })

        RunStore.record_provider_output(run, %{
          "app_server_events" => output["events"],
          "turn" => output["turn"]
        })

        RunStore.append_timeline(run, %{
          "label" => "Codex App Server turn completed",
          "thread_id" => output["thread_id"],
          "turn_id" => output["turn_id"]
        })

        {:ok, output}

      {:error, reason, events} ->
        RunStore.record_provider_output(run, %{"app_server_events" => events})
        {:error, reason}
    end
  end

  defp app_server_opts(run, _params) do
    [
      thread_id: run["codex_thread_id"],
      command: System.get_env("SYMPHONIA_CODEX_APP_SERVER_COMMAND"),
      args: app_server_args()
    ]
  end

  defp mark_run_step(repository, task_key, run, step) do
    run
    |> RunStore.mark_step(step)
    |> sync_task_run(repository, task_key)

    :ok
  end

  defp update_run_metadata(repository, task_key, run, attrs) do
    run
    |> RunStore.update_metadata(attrs)
    |> sync_task_run(repository, task_key)

    :ok
  end

  defp sync_task_run(run, repository, task_key) do
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
      "current_step" => RunEvents.display_step(run),
      "message" => RunEvents.public_message(run),
      "display_step" => RunEvents.display_step(run),
      "display_message" => RunEvents.display_message(run),
      "eligibility_reason" => run["eligibility_reason"],
      "workspace_provider" => run["workspace_provider"],
      "review_branch" => run["review_branch"],
      "curated_summary_id" => run["curated_summary_id"],
      "curated_summary_path" => run["curated_summary_path"],
      "evidence_ids" => run["evidence_ids"],
      "started_at" => run["started_at"],
      "completed_at" => run["completed_at"]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp detect_and_clean_changes(run, repo_path) do
    RunStore.mark_step(run, "Detecting changed files")
    changes = ChangeDetector.detect!(repo_path)
    RunStore.record_provider_output(run, %{"change_detection" => changes})
    BranchManager.revert_paths!(repo_path, changes["excluded"])
    {:ok, changes}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp reviewable_changes(
         run,
         %{workspace_provider: "experimental_sandbox"} = context,
         review_context
       ) do
    RunStore.mark_step(run, "Importing sandbox changes")
    sandbox_changes = ChangeDetector.detect!(context.repo_path)
    changed_paths = Enum.sort(sandbox_changes["committable"] ++ sandbox_changes["excluded"])

    RunStore.record_provider_output(run, %{
      "sandbox_change_detection" => sandbox_changes
    })

    with {:ok, _applied} <-
           ChangeApplier.apply(context.repo_path, review_context.repo_path, changed_paths) do
      detect_and_clean_changes(run, review_context.repo_path)
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp reviewable_changes(run, _context, review_context) do
    detect_and_clean_changes(run, review_context.repo_path)
  end

  defp ensure_committable_changes(%{"committable" => []}) do
    {:error, "The Coding Assistant did not produce any files that can be reviewed."}
  end

  defp ensure_committable_changes(_changes), do: :ok

  defp run_validation(repository, run, repo_path, task) do
    RunStore.mark_step(run, "Running validation")

    policy = Policy.load(repo_path, task)
    {:ok, results} = Runner.run(repo_path, policy)
    public_evidence = Evidence.public(results)

    evidence_records =
      PrivateWorkspace.record_validation_evidence(repository, run, public_evidence)

    evidence_ids = Enum.map(evidence_records, & &1["id"])
    RunStore.update_metadata(run, %{"evidence_ids" => evidence_ids})

    RunStore.record_provider_output(run, %{
      "validation" => %{
        "policy" => policy,
        "results" => results
      }
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

  defp write_summary(repository, run, task, changes, output, validation_evidence) do
    summary =
      CuratedSummary.write_private!(
        repository,
        task,
        RunStore.get(run["id"]) || run,
        changes["committable"],
        output["last_message"],
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

  defp app_server_args do
    case System.get_env("SYMPHONIA_CODEX_APP_SERVER_ARGS") do
      value when is_binary(value) and value != "" -> String.split(value, " ", trim: true)
      _ -> []
    end
  end

  defp force_failure?(params) do
    Map.get(params, "forceFailure") == true or Map.get(params, "force_failure") == true
  end
end
