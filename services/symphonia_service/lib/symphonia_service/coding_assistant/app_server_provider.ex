defmodule SymphoniaService.CodingAssistant.AppServerProvider do
  @moduledoc """
  Coding Assistant provider backed by Codex App Server.
  """

  @behaviour SymphoniaService.CodingAssistant.Provider

  alias SymphoniaService.TaskStore

  alias SymphoniaService.CodingAssistant.{
    AppServerClient,
    BranchManager,
    ChangeDetector,
    ContextPack,
    CuratedSummary,
    HandoffBuilder,
    RunEvents,
    RunStore
  }

  alias SymphoniaService.Runner.LocalGitWorktreeProvider

  @impl true
  def id, do: "codex_app_server"

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
        with {:ok, context} <- LocalGitWorktreeProvider.prepare(repository, task, run, params) do
          RunStore.update_metadata(run, %{
            "workspace_path" => context.repo_path,
            "review_branch" => context.head_branch
          })

          try do
            prompt =
              ContextPack.render_prompt(repository, task, context, params, mode: :app_server)

            with {:ok, output} <-
                   invoke_app_server(repository, task["key"], run, context.repo_path, prompt),
                 {:ok, changes} <- detect_and_clean_changes(run, context.repo_path),
                 :ok <- ensure_committable_changes(changes),
                 {:ok, summary_path} <-
                   write_summary(run, context.repo_path, task, changes, output),
                 :ok <- commit_and_push(run, context, task, changes, summary_path) do
              files_changed = Enum.sort(changes["committable"] ++ [summary_path])

              handoff =
                HandoffBuilder.build_from_changes(
                  task,
                  context,
                  files_changed,
                  output["last_message"]
                )
                |> Map.put("head_branch", context.head_branch)
                |> Map.put("base_branch", context.base_branch)
                |> Map.put("curated_summary_path", summary_path)

              {:ok, handoff}
            else
              {:error, reason} -> {:error, reason}
            end
          after
            LocalGitWorktreeProvider.release(context, %{})
          end
        end
      end
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp branch_preflight(repository, task) do
    BranchManager.ensure_repo_ready_for_task_branch!(repository, task)
    :ok
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

  defp detect_and_clean_changes(run, repo_path) do
    RunStore.mark_step(run, "Detecting changed files")
    changes = ChangeDetector.detect!(repo_path)
    RunStore.record_provider_output(run, %{"change_detection" => changes})
    BranchManager.revert_paths!(repo_path, changes["excluded"])
    {:ok, changes}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp ensure_committable_changes(%{"committable" => []}) do
    {:error, "The Coding Assistant did not produce any files that can be reviewed."}
  end

  defp ensure_committable_changes(_changes), do: :ok

  defp write_summary(run, repo_path, task, changes, output) do
    summary_path =
      CuratedSummary.write!(
        repo_path,
        task,
        RunStore.get(run["id"]) || run,
        changes["committable"],
        output["last_message"]
      )

    RunStore.update_metadata(run, %{"curated_summary_path" => summary_path})
    {:ok, summary_path}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp commit_and_push(run, context, task, changes, summary_path) do
    RunStore.mark_step(run, "Creating review branch")

    BranchManager.commit_files!(
      context,
      task,
      Enum.sort(changes["committable"] ++ [summary_path])
    )

    BranchManager.push_task_branch!(context)
    :ok
  rescue
    error -> {:error, Exception.message(error)}
  end

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
