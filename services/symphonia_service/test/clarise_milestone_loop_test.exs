defmodule SymphoniaService.ClariseMilestoneLoopTest do
  use ExUnit.Case

  alias SymphoniaService.Clarise.MilestoneLoop
  alias SymphoniaService.SpecWorkspace

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphonia-clarise-milestone-loop-test-#{System.unique_integer([:positive])}"
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

  test "start creates a collision-safe draft milestone with stable links", %{repository: repository} do
    SpecWorkspace.initialize(repository)

    File.write!(Path.join(repository["path"], "symphonia/milestones/milestone-001.md"), """
    ---
    type: milestone
    id: milestone-001
    title: Existing milestone
    status: draft
    ---

    # Existing
    """)

    result = MilestoneLoop.start(repository, %{"title" => "Clarise loop"})
    milestone = result["milestone"]

    assert milestone["id"] == "milestone-002"
    assert milestone["status"] == "draft"
    assert milestone["metadata"]["discussion"] == "milestone-002-discussion"
    assert milestone["metadata"]["requirements"] == "milestone-002-requirements"
    assert milestone["metadata"]["plan"] == "milestone-002-plan"
    assert milestone["metadata"]["decisions"] == []
    assert milestone["body"] =~ "# Milestone 002 - Clarise loop"
    assert result["nextStep"] == "discuss"
  end

  test "start initializes missing spec workspace without overwriting existing codebase files", %{
    repository: repository
  } do
    map_path = Path.join(repository["path"], "symphonia/codebase/map.md")
    File.mkdir_p!(Path.dirname(map_path))
    File.write!(map_path, "# Existing map\n\nKeep this.")

    MilestoneLoop.start(repository, %{})

    assert File.read!(map_path) == "# Existing map\n\nKeep this."
    assert File.dir?(Path.join(repository["path"], "symphonia/discussions"))
  end

  test "discussion creates linked artifact and preserves user answers verbatim", %{
    repository: repository
  } do
    milestone = MilestoneLoop.start(repository, %{})["milestone"]

    answer = "Ship a guided loop.\nKeep every answer exactly as typed."

    result =
      MilestoneLoop.discuss(repository, milestone["id"], %{
        "title" => "Guided setup",
        "goal" => "Turn an idea into an approved milestone.",
        "answers" => %{
          "accomplish" => answer,
          "why" => "Users need a reliable planning path."
        }
      })

    discussion = result["discussion"]
    milestone = result["milestone"]

    assert milestone["status"] == "in_discussion"
    assert milestone["title"] == "Guided setup"
    assert discussion["id"] == "milestone-001-discussion"
    assert discussion["metadata"]["related_milestone"] == "milestone-001"
    assert discussion["body"] =~ answer
    assert discussion["body"] =~ "Users need a reliable planning path."
  end

  test "requirements and plan generation create stable linked artifacts", %{repository: repository} do
    milestone = complete_discussion(repository)

    requirements_result = MilestoneLoop.requirements(repository, milestone["id"])
    requirements = requirements_result["requirements"]
    milestone = requirements_result["milestone"]

    assert milestone["status"] == "requirements_ready"
    assert requirements["id"] == "milestone-001-requirements"
    assert requirements["metadata"]["related_milestone"] == "milestone-001"
    assert requirements["body"] =~ "## Acceptance criteria"

    plan_result = MilestoneLoop.plan(repository, milestone["id"])
    plan = plan_result["plan"]
    milestone = plan_result["milestone"]

    assert milestone["status"] == "plan_ready"
    assert plan["id"] == "milestone-001-plan"
    assert plan["metadata"]["related_milestone"] == "milestone-001"
    assert plan["body"] =~ "## Ready for approval checklist"
  end

  test "decision creation links decision to milestone", %{repository: repository} do
    milestone = complete_discussion(repository)

    result =
      MilestoneLoop.decision(repository, milestone["id"], %{
        "title" => "Use Markdown artifacts",
        "body" => "# Use Markdown artifacts\n\n## Decision\n\nKeep the workspace in Markdown."
      })

    decision = result["decision"]
    milestone = result["milestone"]

    assert decision["id"] == "decision-001"
    assert decision["status"] == "approved"
    assert decision["metadata"]["related_milestone"] == "milestone-001"
    assert milestone["metadata"]["decisions"] == ["decision-001"]
  end

  test "approval requires discussion, requirements, and plan", %{repository: repository} do
    milestone = MilestoneLoop.start(repository, %{})["milestone"]

    assert_raise ArgumentError, "Discussion artifact is required.", fn ->
      MilestoneLoop.approve(repository, milestone["id"])
    end

    milestone = complete_discussion(repository, milestone["id"])

    assert_raise ArgumentError, "Requirements artifact is required.", fn ->
      MilestoneLoop.approve(repository, milestone["id"])
    end

    milestone = MilestoneLoop.requirements(repository, milestone["id"])["milestone"]

    assert_raise ArgumentError, "Plan artifact is required.", fn ->
      MilestoneLoop.approve(repository, milestone["id"])
    end
  end

  test "approval marks milestone approved and appends approval section once", %{repository: repository} do
    milestone = complete_discussion(repository)
    milestone = MilestoneLoop.requirements(repository, milestone["id"])["milestone"]
    milestone = MilestoneLoop.plan(repository, milestone["id"])["milestone"]

    approved = MilestoneLoop.approve(repository, milestone["id"])["milestone"]
    approved_again = MilestoneLoop.approve(repository, milestone["id"])["milestone"]

    assert approved["status"] == "approved"
    assert approved["metadata"]["approved_at"]
    assert approved["body"] =~ "## Approval"
    assert approved["body"] =~ "This milestone is approved for implementation planning."
    assert length(Regex.scan(~r/^## Approval$/m, approved_again["body"])) == 1
  end

  test "unsafe milestone ids are rejected", %{repository: repository} do
    MilestoneLoop.start(repository, %{})

    assert_raise ArgumentError, "Unsafe spec artifact id.", fn ->
      MilestoneLoop.approve(repository, "../secret")
    end
  end

  defp complete_discussion(repository, existing_id \\ nil) do
    milestone =
      case existing_id do
        nil -> MilestoneLoop.start(repository, %{})["milestone"]
        id -> SpecWorkspace.read_artifact(repository, "milestone", id)
      end

    MilestoneLoop.discuss(repository, milestone["id"], %{
      "title" => "Clarise milestone loop",
      "goal" => "Turn vague intent into approved planning artifacts.",
      "answers" => %{
        "accomplish" => "Users can start and approve a milestone.",
        "why" => "Milestones need durable context.",
        "include" => "Discussion, requirements, plan, decisions, approval.",
        "exclude" => "No task generation.",
        "complete" => "All artifacts are linked.",
        "codebase" => "Spec workspace service and workspace UI.",
        "risks" => "Avoid confusing task statuses and milestone statuses."
      }
    })["milestone"]
  end
end
