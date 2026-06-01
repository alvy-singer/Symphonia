defmodule SymphoniaService.ContextPackTest do
  use ExUnit.Case

  alias SymphoniaService.{
    CodingAssistant.ContextPack,
    RepositoryRegistry,
    SpecWorkspace,
    TaskStore,
    Workspace
  }

  alias SymphoniaService.CodingAssistant.RunStore

  setup do
    root =
      Path.join(System.tmp_dir!(), "symphonia-context-pack-#{System.unique_integer([:positive])}")

    repo_path = Path.join(root, "repo")
    registry_path = Path.join(root, "registry.json")
    runs_root = Path.join(root, "runs")
    File.mkdir_p!(Path.join(repo_path, ".git"))

    previous_runs_root = System.get_env("SYMPHONIA_RUNS_ROOT")
    System.put_env("SYMPHONIA_RUNS_ROOT", runs_root)

    on_exit(fn ->
      restore_env("SYMPHONIA_RUNS_ROOT", previous_runs_root)
      File.rm_rf(root)
    end)

    repository = RepositoryRegistry.add(registry_path, %{"path" => repo_path, "key" => "SYM"})
    Workspace.initialize(repository)
    Workspace.create_workflow_from_template(repository, "review-first")
    SpecWorkspace.initialize(repository)

    SpecWorkspace.update_artifact(repository, "codebase_map", "codebase-map", %{
      "body" => "# Codebase Map\n\nRelevant service and UI boundaries."
    })

    SpecWorkspace.create_artifact(repository, "milestone", "milestone-approved", %{
      "title" => "Approved milestone",
      "status" => "approved",
      "body" => "# Approved milestone\n\nShip the harness."
    })

    SpecWorkspace.create_artifact(repository, "milestone", "milestone-draft", %{
      "title" => "Draft milestone",
      "status" => "draft",
      "body" => "# Draft milestone\n\nDo not include this."
    })

    SpecWorkspace.create_artifact(repository, "requirements", "requirements-1", %{
      "title" => "Harness requirements",
      "body" => "# Harness requirements\n\nLocal-first execution."
    })

    SpecWorkspace.create_artifact(repository, "plan", "plan-1", %{
      "title" => "Harness plan",
      "body" => "# Harness plan\n\nDaemon before UI."
    })

    SpecWorkspace.create_artifact(repository, "plan", "plan-unlinked", %{
      "title" => "Unlinked plan",
      "body" => "# Unlinked plan\n\nDo not include this."
    })

    SpecWorkspace.create_artifact(repository, "decision", "decision-1", %{
      "title" => "Codex only",
      "body" => "# Codex only\n\nHarness runs Codex App Server."
    })

    task_body = """
    # Implement always-on harness

    Use existing daemon.

    ## Review notes

    Original feedback:
    This raw reviewer complaint should stay out of the provider prompt.

    Requested changes:
    - Keep the stream observer bounded.

    ## Handoff history

    Older private handoff detail should not be replayed.
    """

    task =
      TaskStore.create_task(registry_path, repository, %{
        "title" => "Implement always-on harness",
        "body" => task_body,
        "source_milestone" => "milestone-approved",
        "source_requirements" => "requirements-1",
        "source_plan" => "plan-1",
        "source_decisions" => ["decision-1"],
        "review_expectations" => ["Daemon dispatches one task."]
      })

    run =
      RunStore.create(
        %{
          "provider" => "codex_app_server",
          "repository" => repository["key"],
          "task" => task["key"],
          "codex_thread_id" => "thread-private",
          "turn_id" => "turn-private"
        },
        root: runs_root
      )

    RunStore.record_provider_output(
      run,
      %{
        "app_server_events" => [
          %{"method" => "agent/message/delta", "params" => %{"text" => "raw transcript secret"}}
        ],
        "turn" => %{"id" => "turn-private", "transcript" => "private turn transcript"}
      },
      root: runs_root
    )

    task =
      TaskStore.patch_task(repository, task["key"], %{
        "frontmatter" => %{
          "handoff" => %{
            "summary" => "Previous handoff summary.",
            "files_changed" => ["app/previous-output.txt"],
            "head_branch" => "symphonia/task/sym-1",
            "curated_summary_path" => "symphonia/run-summaries/sym-1.md"
          },
          "run" => %{
            "codex_thread_id" => "thread-legacy",
            "turn_id" => "turn-frontmatter-secret"
          }
        }
      })

    %{repository: repository, root: root, runs_root: runs_root, task: task}
  end

  test "builds linked context plus canonical codebase map and renders provider prompts from it",
       %{
         repository: repository,
         root: root,
         runs_root: runs_root,
         task: task
       } do
    context = %{
      base_branch: "main",
      head_branch: "symphonia/task/sym-1",
      repo_path: repository["path"],
      persistent: true,
      workspace_provider: "local_git_worktree"
    }

    pack = ContextPack.build(repository, task, context, %{"assistant_input" => "Address review."})
    artifact_ids = Enum.map(pack["artifacts"], & &1["id"])

    assert "codebase-map" in artifact_ids
    assert "milestone-approved" in artifact_ids
    assert "requirements-1" in artifact_ids
    assert "plan-1" in artifact_ids
    assert "decision-1" in artifact_ids
    refute "milestone-draft" in artifact_ids
    refute "plan-unlinked" in artifact_ids
    assert pack["previousHandoff"]["summary"] == "Previous handoff summary."
    assert "app/previous-output.txt" in pack["previousHandoff"]["filesChanged"]
    assert pack["reviewNotes"] =~ "Requested changes:"
    refute pack["reviewNotes"] =~ "raw reviewer complaint"
    assert pack["existingCodexThreadId"] == "thread-private"

    prompt =
      ContextPack.render_prompt(
        repository,
        task,
        context,
        %{"assistant_input" => "Address review."},
        mode: :app_server
      )

    assert prompt =~ "Task key: #{task["key"]}"
    assert prompt =~ "Continuation input:\nAddress review."
    assert prompt =~ "Approved milestone"
    assert prompt =~ "Harness requirements"
    assert prompt =~ "Harness plan"
    assert prompt =~ "Codex only"
    assert prompt =~ "Workspace provider: local_git_worktree"
    assert prompt =~ "Previous handoff:"
    assert prompt =~ "Previous handoff summary."
    assert prompt =~ "app/previous-output.txt"
    assert prompt =~ "Review notes:"
    assert prompt =~ "Requested changes:"
    assert prompt =~ "- Keep the stream observer bounded."
    refute prompt =~ "Unlinked plan"
    refute prompt =~ "Draft milestone"
    refute prompt =~ repository["path"]
    refute prompt =~ "Existing Codex thread ID"
    refute prompt =~ "thread-private"
    refute prompt =~ "raw reviewer complaint"
    refute prompt =~ "Older private handoff detail"
    refute prompt =~ "turn-private"
    refute prompt =~ "turn-frontmatter-secret"
    refute prompt =~ "raw transcript secret"
    refute prompt =~ "private turn transcript"
    refute prompt =~ runs_root
    refute prompt =~ root <> "/runs"
  end

  test "app-server and legacy codex modes share the same ContextPack source", %{
    repository: repository,
    task: task
  } do
    context = %{
      base_branch: "main",
      head_branch: "symphonia/task/sym-1",
      repo_path: repository["path"],
      persistent: true,
      workspace_provider: "local_git_worktree"
    }

    params = %{"assistant_input" => "Address review."}

    app_server_prompt =
      ContextPack.render_prompt(repository, task, context, params, mode: :app_server)

    codex_prompt = ContextPack.render_prompt(repository, task, context, params, mode: :codex)

    assert app_server_prompt =~ "persistent task workspace"
    assert codex_prompt =~ "repository workspace"

    for shared <- [
          "Task key: #{task["key"]}",
          "Continuation input:\nAddress review.",
          "Codebase Map",
          "Approved milestone",
          "Harness requirements",
          "Harness plan",
          "Codex only",
          "Previous handoff summary.",
          "Review notes:"
        ] do
      assert app_server_prompt =~ shared
      assert codex_prompt =~ shared
    end

    for private <- [
          "Unlinked plan",
          "Draft milestone",
          "thread-private",
          "turn-private",
          "raw transcript secret",
          repository["path"]
        ] do
      refute app_server_prompt =~ private
      refute codex_prompt =~ private
    end
  end

  test "gemini prompt is rendered from ContextPack without Codex thread or private output", %{
    repository: repository,
    root: root,
    runs_root: runs_root,
    task: task
  } do
    context = %{
      base_branch: "main",
      head_branch: "symphonia/task/sym-1",
      repo_path: "sandbox source-bundle workspace",
      persistent: false,
      workspace_provider: "cloud_sandbox"
    }

    provider_context =
      ContextPack.provider_context(
        repository,
        task,
        context,
        %{"assistant_input" => "Address review."},
        provider: :gemini_cli
      )

    prompt = provider_context["renderedPrompt"]

    assert provider_context["provider"] == "gemini_cli"
    assert prompt =~ "OpenSandbox source-bundle workspace"
    assert prompt =~ "Task key: #{task["key"]}"
    assert prompt =~ "Approved milestone"
    assert prompt =~ "Harness requirements"
    assert prompt =~ "Do not rely on ambient Gemini memory"
    assert prompt =~ "Leave validation authority to Symphonía"

    refute prompt =~ "Existing Codex thread ID"
    refute prompt =~ "thread-private"
    refute prompt =~ "turn-private"
    refute prompt =~ "raw transcript secret"
    refute prompt =~ "private turn transcript"
    refute prompt =~ runs_root
    refute prompt =~ root <> "/runs"
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
