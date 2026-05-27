defmodule SymphoniaService.SpecWorkspaceTest do
  use ExUnit.Case

  alias SymphoniaService.SpecWorkspace

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphonia-spec-workspace-test-#{System.unique_integer([:positive])}"
      )

    repo_path = Path.join(root, "repo")
    File.mkdir_p!(repo_path)

    on_exit(fn -> File.rm_rf(root) end)

    %{
      root: root,
      repository: %{
        "key" => "SYM",
        "name" => "repo",
        "path" => repo_path,
        "last_task_number" => 0
      }
    }
  end

  test "detects and initializes spec workspace with default codebase artifacts", %{
    repository: repository
  } do
    state = SpecWorkspace.state(repository)

    refute state["initialized"]
    assert "symphonia/codebase" in state["missingDirectories"]
    assert "codebase_map" in state["missingDefaultArtifacts"]

    initialized = SpecWorkspace.initialize(repository)

    assert initialized["exists"]
    assert initialized["initialized"]
    assert initialized["missingDirectories"] == []
    assert initialized["missingDefaultArtifacts"] == []

    assert File.exists?(Path.join(repository["path"], "symphonia/codebase/map.md"))
    assert File.exists?(Path.join(repository["path"], "symphonia/codebase/conventions.md"))
    assert File.exists?(Path.join(repository["path"], "symphonia/codebase/architecture.md"))
  end

  test "does not overwrite existing codebase files during initialization", %{
    repository: repository
  } do
    map_path = Path.join(repository["path"], "symphonia/codebase/map.md")
    File.mkdir_p!(Path.dirname(map_path))
    File.write!(map_path, "# Existing map\n\nKeep this.")

    SpecWorkspace.initialize(repository)
    SpecWorkspace.initialize(repository)

    assert File.read!(map_path) == "# Existing map\n\nKeep this."
  end

  test "creates collision-safe milestone and decision ids", %{repository: repository} do
    SpecWorkspace.initialize(repository)

    milestone_dir = Path.join(repository["path"], "symphonia/milestones")
    decision_dir = Path.join(repository["path"], "symphonia/decisions")

    File.write!(Path.join(milestone_dir, "milestone-001.md"), """
    ---
    type: milestone
    id: milestone-001
    title: Existing one
    status: draft
    ---

    # Existing
    """)

    File.write!(Path.join(milestone_dir, "custom.md"), """
    ---
    type: milestone
    id: milestone-007
    title: Existing seven
    status: draft
    ---

    # Existing
    """)

    File.write!(Path.join(decision_dir, "decision-001.md"), """
    ---
    type: decision
    id: decision-001
    title: Existing decision
    status: draft
    ---

    # Existing
    """)

    milestone = SpecWorkspace.create_milestone(repository, %{"title" => "Next milestone"})
    decision = SpecWorkspace.create_decision(repository, %{"title" => "Next decision"})

    assert milestone["id"] == "milestone-008"
    assert milestone["path"] == "symphonia/milestones/milestone-008.md"
    assert milestone["body"] =~ "# Milestone 008 — Next milestone"

    assert decision["id"] == "decision-002"
    assert decision["path"] == "symphonia/decisions/decision-002.md"
    assert decision["body"] =~ "# Decision 002 — Next decision"
  end

  test "creates private task brief artifacts without task board side effects", %{repository: repository} do
    SpecWorkspace.initialize(repository)

    task_brief =
      SpecWorkspace.create_task_brief(repository, %{
        "title" => "Set up WORKFLOW.md",
        "body" => "# Set up WORKFLOW.md\n\n## Goal\n\nPrepare repository rules privately.",
        "private" => true,
        "source" => "clarise_chat"
      })

    assert task_brief["type"] == "task_brief"
    assert task_brief["id"] == "task-001"
    assert task_brief["path"] == "symphonia/task-briefs/task-001.md"
    assert task_brief["metadata"]["private"] == true
    assert task_brief["metadata"]["source"] == "clarise_chat"
    refute File.exists?(Path.join(repository["path"], "symphonia/tasks/SYM-1.md"))
  end

  test "creates requirement and plan artifacts with milestone metadata", %{repository: repository} do
    SpecWorkspace.initialize(repository)
    milestone = SpecWorkspace.create_milestone(repository, %{"title" => "Planning parent"})

    requirement =
      SpecWorkspace.create_requirement(repository, %{
        "title" => "Private requirement",
        "body" => "# Requirement\n\n## Requirement\n\nKeep project memory durable.",
        "related_milestone" => milestone["id"],
        "private" => true
      })

    plan =
      SpecWorkspace.create_plan(repository, %{
        "title" => "Private plan",
        "body" => "# Plan\n\n## Plan\n\nCreate docs first.",
        "related_milestone" => milestone["id"],
        "private" => true
      })

    assert requirement["id"] == "requirement-001"
    assert requirement["metadata"]["related_milestone"] == milestone["id"]
    assert plan["id"] == "plan-001"
    assert plan["metadata"]["related_milestone"] == milestone["id"]
  end

  test "lists, reads, and updates artifacts while preserving metadata", %{repository: repository} do
    SpecWorkspace.initialize(repository)
    artifact = SpecWorkspace.create_milestone(repository, %{"title" => "Editable milestone"})

    assert [listed] = SpecWorkspace.list_artifacts(repository, "milestone")
    assert listed["id"] == artifact["id"]

    read = SpecWorkspace.read_artifact(repository, "milestone", artifact["id"])

    updated =
      SpecWorkspace.update_artifact(repository, "milestone", artifact["id"], %{
        "body" => "# Changed milestone\n\nUpdated body."
      })

    assert updated["body"] =~ "Updated body."
    assert updated["metadata"]["type"] == "milestone"
    assert updated["metadata"]["id"] == artifact["id"]
    assert updated["metadata"]["status"] == "draft"
    assert updated["metadata"]["created_at"] == read["metadata"]["created_at"]
    assert updated["metadata"]["source"] == "clarise"
  end

  test "updates metadata safely and rejects task statuses", %{repository: repository} do
    SpecWorkspace.initialize(repository)
    decision = SpecWorkspace.create_decision(repository, %{"title" => "Metadata decision"})

    updated =
      SpecWorkspace.update_artifact(repository, "decision", decision["id"], %{
        "metadata" => %{
          "title" => "Approved decision",
          "status" => "approved",
          "type" => "decision",
          "id" => decision["id"]
        }
      })

    assert updated["title"] == "Approved decision"
    assert updated["status"] == "approved"

    assert_raise ArgumentError, "Unknown spec artifact status.", fn ->
      SpecWorkspace.update_artifact(repository, "decision", decision["id"], %{
        "metadata" => %{"status" => "completed"}
      })
    end

    assert_raise ArgumentError, "Spec artifact id cannot be changed.", fn ->
      SpecWorkspace.update_artifact(repository, "decision", decision["id"], %{
        "metadata" => %{"id" => "decision-999"}
      })
    end
  end

  test "rejects unsafe paths and path traversal", %{repository: repository} do
    SpecWorkspace.initialize(repository)

    assert_raise ArgumentError, "Unsafe spec artifact id.", fn ->
      SpecWorkspace.read_artifact(repository, "milestone", "../secret")
    end

    assert_raise ArgumentError, "Unsafe spec artifact id.", fn ->
      SpecWorkspace.update_artifact(repository, "decision", "decision-001/../../secret", %{})
    end

    assert_raise ArgumentError, "Unknown spec artifact type.", fn ->
      SpecWorkspace.list_artifacts(repository, "../../tasks")
    end
  end
end
