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

    task =
      TaskStore.create_task(registry_path, repository, %{
        "title" => "Implement always-on harness",
        "body" => "# Implement always-on harness\n\nUse existing daemon.",
        "source_milestone" => "milestone-approved",
        "source_requirements" => "requirements-1",
        "source_plan" => "plan-1",
        "source_decisions" => ["decision-1"],
        "review_expectations" => ["Daemon dispatches one task."]
      })

    RunStore.create(
      %{
        "provider" => "codex_app_server",
        "repository" => repository["key"],
        "task" => task["key"],
        "codex_thread_id" => "thread-private"
      },
      root: runs_root
    )

    %{repository: repository, task: TaskStore.get_task(repository, task["key"])}
  end

  test "builds linked-only context and renders provider prompts from it", %{
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

    pack = ContextPack.build(repository, task, context, %{"assistant_input" => "Address review."})
    artifact_ids = Enum.map(pack["artifacts"], & &1["id"])

    assert "codebase-map" in artifact_ids
    assert "milestone-approved" in artifact_ids
    assert "requirements-1" in artifact_ids
    assert "plan-1" in artifact_ids
    assert "decision-1" in artifact_ids
    refute "milestone-draft" in artifact_ids
    refute "plan-unlinked" in artifact_ids
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
    assert prompt =~ "Existing Codex thread ID: thread-private"
    refute prompt =~ "Unlinked plan"
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
