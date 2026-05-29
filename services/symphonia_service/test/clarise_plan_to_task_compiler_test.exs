defmodule SymphoniaService.ClarisePlanToTaskCompilerTest do
  use ExUnit.Case

  alias SymphoniaService.Clarise.{MilestoneLoop, PlanToTaskCompiler}
  alias SymphoniaService.{RepositoryRegistry, SpecWorkspace, TaskStore}

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphonia-plan-to-task-compiler-test-#{System.unique_integer([:positive])}"
      )

    repo_path = Path.join(root, "repo")
    registry_path = Path.join(root, "registry.json")
    File.mkdir_p!(repo_path)
    File.mkdir_p!(Path.join(repo_path, ".git"))

    on_exit(fn -> File.rm_rf(root) end)

    repository = RepositoryRegistry.add(registry_path, %{"path" => repo_path, "key" => "SYM"})

    %{
      root: root,
      repo_path: repo_path,
      registry_path: registry_path,
      repository: repository
    }
  end

  test "proposal requires an approved milestone", %{repository: repository} do
    milestone = MilestoneLoop.start(repository, %{"title" => "Task compiler"})["milestone"]

    assert_raise ArgumentError, "Milestone must be approved before generating tasks.", fn ->
      PlanToTaskCompiler.propose(repository, milestone["id"])
    end
  end

  test "proposal persists a task proposal artifact and is deterministic", %{
    repository: repository
  } do
    milestone = approved_milestone(repository)

    first = PlanToTaskCompiler.propose(repository, milestone["id"])
    second = PlanToTaskCompiler.propose(repository, milestone["id"])
    proposal = first["proposal"]

    assert proposal["type"] == "task_proposal"
    assert proposal["id"] == "milestone-001-task-proposal"
    assert proposal["status"] == "draft"
    assert proposal["metadata"]["source_milestone"] == "milestone-001"
    assert proposal["metadata"]["source_plan"] == "milestone-001-plan"
    assert proposal["metadata"]["generation_id"] == "milestone-001-plan-to-task-v2"

    assert [%{"id" => "milestone-001-task-001", "selected" => true} | _] =
             proposal["metadata"]["proposal_items"]

    assert proposal["metadata"]["source_discussion"] == "milestone-001-discussion"
    assert proposal["metadata"]["created_tasks"] == []
    assert proposal["path"] == "symphonia/task-proposals/milestone-001-task-proposal.md"
    assert proposal["body"] =~ "## Proposed tasks"
    assert proposal["body"] =~ "## Harness readiness"
    assert first["nextStep"] == "review_task_proposal"
    assert first["taskBoard"] == %{"sourceMilestone" => "milestone-001", "createdTasks" => []}
    assert first["items"] == second["items"]
  end

  test "vague approved plans produce clarification tasks", %{repository: repository} do
    milestone = approved_milestone(repository)

    SpecWorkspace.update_artifact(repository, "plan", "milestone-001-plan", %{
      "body" => "# Vague plan\n\n## Summary\n\nImprove the product."
    })

    result = PlanToTaskCompiler.propose(repository, milestone["id"])

    assert length(result["items"]) == 3
    assert hd(result["items"])["title"] =~ "Clarify implementation scope"
    assert Enum.at(result["items"], 1)["depends_on"] == ["milestone-001-task-001"]
  end

  test "confirmation writes generated tasks with source metadata and resolved dependencies", %{
    registry_path: registry_path,
    repository: repository,
    repo_path: repo_path
  } do
    milestone = approved_milestone(repository, decision?: true)
    PlanToTaskCompiler.propose(repository, milestone["id"])

    result = PlanToTaskCompiler.create_tasks(registry_path, repository, milestone["id"])
    tasks = result["tasks"]

    assert length(tasks) == 5
    assert result["createdCount"] == 5
    assert result["createdTasks"] == ["SYM-1", "SYM-2", "SYM-3", "SYM-4", "SYM-5"]
    assert result["nextStep"] == "task_board"

    assert result["taskBoard"] == %{
             "sourceMilestone" => "milestone-001",
             "createdTasks" => ["SYM-1", "SYM-2", "SYM-3", "SYM-4", "SYM-5"]
           }

    [first, second | _rest] = TaskStore.list_tasks(repository)
    assert first["status"] == "todo"
    assert first["sourceMilestone"] == "milestone-001"
    assert first["sourcePlan"] == "milestone-001-plan"
    assert first["sourceRequirements"] == "milestone-001-requirements"
    assert first["sourceDiscussion"] == "milestone-001-discussion"
    assert first["sourceDecisions"] == ["decision-001"]
    assert first["generatedBy"] == "clarise_plan_to_task"
    assert first["generationId"] == "milestone-001-plan-to-task-v2"
    assert first["proposalItemId"] == "milestone-001-task-001"
    assert first["reviewExpectations"] != []
    assert second["dependsOn"] == ["SYM-1"]

    first_markdown = File.read!(Path.join([repo_path, "symphonia/tasks/SYM-1.md"]))
    assert first_markdown =~ "type: task"
    assert first_markdown =~ "id: SYM-1"
    assert first_markdown =~ "source_milestone: milestone-001"
    assert first_markdown =~ "generation_id: milestone-001-plan-to-task-v2"
    assert first_markdown =~ "proposal_item_id: milestone-001-task-001"

    proposal =
      SpecWorkspace.read_artifact(repository, "task_proposal", "milestone-001-task-proposal")

    assert proposal["status"] == "created"
    assert proposal["metadata"]["created_tasks"] == ["SYM-1", "SYM-2", "SYM-3", "SYM-4", "SYM-5"]
  end

  test "confirmation uses edited proposal payload instead of regenerated defaults", %{
    registry_path: registry_path,
    repository: repository
  } do
    milestone = approved_milestone(repository)
    proposal = PlanToTaskCompiler.propose(repository, milestone["id"])
    [first | rest] = proposal["items"]

    result =
      PlanToTaskCompiler.create_tasks(registry_path, repository, milestone["id"], %{
        "selectedProposalItemIds" => [first["id"]],
        "items" => [
          Map.merge(first, %{
            "title" => "Edited implementation boundary task",
            "priority" => "high",
            "depends_on" => [],
            "acceptance_criteria" => ["Edited acceptance is preserved."],
            "review_expectations" => ["Edited review expectation is preserved."]
          })
          | rest
        ]
      })

    assert result["createdCount"] == 1
    assert result["createdTasks"] == ["SYM-1"]
    [created] = result["tasks"]
    assert created["title"] == "Edited implementation boundary task"
    assert created["priority"] == "high"
    assert created["reviewExpectations"] == ["Edited review expectation is preserved."]
    assert created["body"] =~ "Edited acceptance is preserved."
    assert created["generationId"] == "milestone-001-plan-to-task-v2"
  end

  test "selected-only creation skips unselected items and blocks unresolved dependencies", %{
    registry_path: registry_path,
    repository: repository
  } do
    milestone = approved_milestone(repository)
    proposal = PlanToTaskCompiler.propose(repository, milestone["id"])
    [_first, second | _rest] = proposal["items"]

    blocked =
      PlanToTaskCompiler.create_tasks(registry_path, repository, milestone["id"], %{
        "selectedProposalItemIds" => [second["id"]]
      })

    assert blocked["createdCount"] == 0
    assert blocked["nextStep"] == "resolve_dependencies"

    assert Enum.any?(
             blocked["blockers"],
             &String.contains?(&1, "is not selected or already created")
           )

    assert TaskStore.list_tasks(repository) == []

    first = hd(proposal["items"])

    created =
      PlanToTaskCompiler.create_tasks(registry_path, repository, milestone["id"], %{
        "selectedProposalItemIds" => [first["id"]]
      })

    assert created["createdCount"] == 1
    assert created["createdTasks"] == ["SYM-1"]
    assert TaskStore.list_tasks(repository) |> length() == 1
  end

  test "duplicate detection reuses existing v1 generated tasks", %{
    registry_path: registry_path,
    repository: repository
  } do
    milestone = approved_milestone(repository)

    TaskStore.create_task(registry_path, repository, %{
      "title" => "Existing V1 generated task",
      "description" => "# Existing V1 generated task\n\nAlready created.",
      "priority" => "medium",
      "project" => milestone["id"],
      "type" => "task",
      "source_milestone" => milestone["id"],
      "source_plan" => "milestone-001-plan",
      "source_requirements" => "milestone-001-requirements",
      "source_discussion" => "milestone-001-discussion",
      "generated_by" => "clarise_plan_to_task",
      "generation_id" => "milestone-001-plan-to-task-v1",
      "proposal_item_id" => "milestone-001-task-001",
      "depends_on" => [],
      "review_expectations" => ["Existing task remains linked."]
    })

    PlanToTaskCompiler.propose(repository, milestone["id"])

    result =
      PlanToTaskCompiler.create_tasks(registry_path, repository, milestone["id"], %{
        "selectedProposalItemIds" => ["milestone-001-task-001"]
      })

    assert result["createdCount"] == 0
    assert result["createdTasks"] == ["SYM-1"]
    assert [%{"reason" => "Task already exists."}] = result["skipped"]
    assert TaskStore.list_tasks(repository) |> length() == 1
  end

  test "repeated confirmation does not duplicate tasks from the same proposal", %{
    registry_path: registry_path,
    repository: repository
  } do
    milestone = approved_milestone(repository)
    PlanToTaskCompiler.propose(repository, milestone["id"])

    first = PlanToTaskCompiler.create_tasks(registry_path, repository, milestone["id"])
    second = PlanToTaskCompiler.create_tasks(registry_path, repository, milestone["id"])

    assert first["createdTasks"] == second["createdTasks"]
    assert second["createdCount"] == 0
    assert TaskStore.list_tasks(repository) |> length() == 5
  end

  test "confirmation requires a persisted proposal", %{
    registry_path: registry_path,
    repository: repository
  } do
    milestone = approved_milestone(repository)

    assert_raise ArgumentError, "Task proposal is required before creating tasks.", fn ->
      PlanToTaskCompiler.create_tasks(registry_path, repository, milestone["id"])
    end
  end

  test "unsafe milestone ids are rejected", %{repository: repository} do
    assert_raise ArgumentError, "Unsafe spec artifact id.", fn ->
      PlanToTaskCompiler.propose(repository, "../secret")
    end
  end

  defp approved_milestone(repository, opts \\ []) do
    milestone =
      MilestoneLoop.start(repository, %{"title" => "Plan to task compiler"})["milestone"]

    milestone =
      MilestoneLoop.discuss(repository, milestone["id"], %{
        "title" => "Plan to task compiler",
        "goal" => "Turn an approved milestone plan into reviewed task files.",
        "answers" => %{
          "accomplish" => "Create task files from an approved plan.",
          "why" => "Users need a bridge from planning to implementation.",
          "include" => "Proposal, review, task creation, dependency metadata.",
          "exclude" => "No Coding Assistant run starts automatically.",
          "complete" => "Tasks show on the board as To-do.",
          "codebase" => "Clarise service, task store, workspace UI.",
          "risks" => "Avoid duplicate tasks and preserve source links."
        }
      })["milestone"]

    if Keyword.get(opts, :decision?, false) do
      MilestoneLoop.decision(repository, milestone["id"], %{
        "title" => "Keep task creation deliberate",
        "body" =>
          "# Keep task creation deliberate\n\n## Decision\n\nDo not start work automatically."
      })
    end

    milestone = MilestoneLoop.requirements(repository, milestone["id"])["milestone"]
    milestone = MilestoneLoop.plan(repository, milestone["id"])["milestone"]
    MilestoneLoop.approve(repository, milestone["id"])["milestone"]
  end
end
