defmodule SymphoniaService.WorkspaceTest do
  use ExUnit.Case

  alias SymphoniaService.Workspace

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphonia-workspace-test-#{System.unique_integer([:positive])}"
      )

    repo_path = Path.join(root, "repo")
    File.mkdir_p!(repo_path)

    on_exit(fn -> File.rm_rf(root) end)

    %{
      repository: %{
        "key" => "SYM",
        "name" => "repo",
        "path" => repo_path,
        "last_task_number" => 0
      }
    }
  end

  test "detects missing workspace state", %{repository: repository} do
    state = Workspace.state(repository)

    refute state["initialized"]
    assert "symphonia/tasks" in state["missingDirectories"]
    refute state["workflow"]["exists"]
  end

  test "initializes folders without touching WORKFLOW.md", %{repository: repository} do
    workflow_path = Path.join(repository["path"], "WORKFLOW.md")
    File.write!(workflow_path, "existing workflow")

    state = Workspace.initialize(repository)
    second_state = Workspace.initialize(repository)

    assert state["initialized"]
    assert second_state["missingDirectories"] == []
    assert File.read!(workflow_path) == "existing workflow"
  end

  test "creates workflow from template only when missing", %{repository: repository} do
    workflow = Workspace.create_workflow_from_template(repository, "simple-pr")

    assert workflow["exists"]
    assert workflow["body"] =~ "Simple PR workflow"

    assert_raise ArgumentError, "WORKFLOW.md already exists.", fn ->
      Workspace.create_workflow_from_template(repository, "review-first")
    end
  end

  test "updates workflow as a repository file", %{repository: repository} do
    workflow = Workspace.update_workflow(repository, "# WORKFLOW.md\n\non_task_started:\n")

    assert workflow["exists"]
    assert workflow["body"] =~ "on_task_started:"
    assert File.read!(Path.join(repository["path"], "WORKFLOW.md")) == workflow["body"]
  end
end
