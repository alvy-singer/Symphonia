defmodule SymphoniaService.Clarise.PlanToTaskCompiler do
  @moduledoc """
  Deterministic Clarise bridge from an approved milestone plan to task files.
  """

  alias SymphoniaService.{SpecWorkspace, TaskStore}
  alias SymphoniaService.SpecWorkspace.Store

  @generated_by "clarise_plan_to_task"

  def propose(repository, milestone_id, payload \\ %{}) do
    SpecWorkspace.initialize(repository)
    sources = load_sources(repository, milestone_id)
    items = proposal_items(sources)
    generation_id = generation_id(milestone_id)
    proposal_id = proposal_id(milestone_id)
    existing = read_existing_proposal(repository, proposal_id)
    regenerate? = truthy?(Map.get(payload, "regenerate"))

    status =
      if existing && existing["status"] == "created" && !regenerate? do
        "created"
      else
        "draft"
      end

    created_tasks =
      if status == "created" do
        list_metadata(existing, "created_tasks")
      else
        []
      end

    proposal =
      Store.create_or_update_artifact(repository, "task_proposal", proposal_id, %{
        "title" => "#{sources.milestone["title"]} task proposal",
        "status" => status,
        "source_milestone" => sources.milestone["id"],
        "source_plan" => sources.plan["id"],
        "source_requirements" => sources.requirements["id"],
        "source_discussion" => sources.discussion["id"],
        "source_decisions" => Enum.map(sources.decisions, & &1["id"]),
        "generated_by" => @generated_by,
        "generation_id" => generation_id,
        "created_tasks" => created_tasks,
        "body" => proposal_body(sources, items, created_tasks)
      })

    %{
      "proposal" => proposal,
      "items" => Enum.map(items, &public_item/1),
      "generationId" => generation_id,
      "createdTasks" => created_tasks,
      "nextStep" => if(created_tasks == [], do: "review_task_proposal", else: "task_board"),
      "taskBoard" => task_board_payload(sources.milestone["id"], created_tasks)
    }
  end

  def create_tasks(registry_path, repository, milestone_id, _payload \\ %{}) do
    SpecWorkspace.initialize(repository)
    sources = load_sources(repository, milestone_id)
    proposal_id = proposal_id(milestone_id)
    generation_id = generation_id(milestone_id)

    unless Store.artifact_exists?(repository, "task_proposal", proposal_id) do
      raise ArgumentError, "Task proposal is required before creating tasks."
    end

    items = proposal_items(sources)

    initial_mapping =
      repository
      |> TaskStore.list_tasks()
      |> existing_generated_tasks(generation_id)

    {mapping, tasks, created_count} =
      Enum.reduce(items, {initial_mapping, [], 0}, fn item, {mapping, tasks, created_count} ->
        case Map.get(mapping, item.id) do
          nil ->
            depends_on = resolve_dependencies(item.depends_on, mapping)

            task =
              TaskStore.create_task(registry_path, repository, %{
                "title" => item.title,
                "description" => task_body(item, sources),
                "priority" => item.priority,
                "project" => sources.milestone["id"],
                "type" => "task",
                "source_milestone" => sources.milestone["id"],
                "source_plan" => sources.plan["id"],
                "source_requirements" => sources.requirements["id"],
                "source_discussion" => sources.discussion["id"],
                "source_decisions" => Enum.map(sources.decisions, & &1["id"]),
                "generated_by" => @generated_by,
                "generation_id" => generation_id,
                "proposal_item_id" => item.id,
                "depends_on" => depends_on,
                "review_expectations" => item.review_expectations
              })

            {Map.put(mapping, item.id, task["key"]), tasks ++ [task], created_count + 1}

          key ->
            task = TaskStore.get_task(repository, key)
            {mapping, tasks ++ List.wrap(task), created_count}
        end
      end)

    created_tasks = items |> Enum.map(&Map.fetch!(mapping, &1.id))

    proposal =
      Store.update_artifact(repository, "task_proposal", proposal_id, %{
        "metadata" => %{
          "status" => "created",
          "created_tasks" => created_tasks,
          "generation_id" => generation_id
        },
        "body" => proposal_body(sources, items, created_tasks)
      })

    %{
      "proposal" => proposal,
      "items" => Enum.map(items, &public_item/1),
      "tasks" => Enum.map(tasks, &public_task/1),
      "createdTasks" => created_tasks,
      "createdCount" => created_count,
      "generationId" => generation_id,
      "nextStep" => "task_board",
      "taskBoard" => task_board_payload(sources.milestone["id"], created_tasks)
    }
  end

  defp load_sources(repository, milestone_id) do
    milestone = SpecWorkspace.read_artifact(repository, "milestone", milestone_id)

    unless milestone["status"] == "approved" do
      raise ArgumentError, "Milestone must be approved before generating tasks."
    end

    discussion_id = metadata_id!(milestone, "discussion", "Discussion artifact is required.")
    requirements_id = metadata_id!(milestone, "requirements", "Requirements artifact is required.")
    plan_id = metadata_id!(milestone, "plan", "Plan artifact is required.")

    %{
      milestone: milestone,
      discussion: SpecWorkspace.read_artifact(repository, "discussion", discussion_id),
      requirements: SpecWorkspace.read_artifact(repository, "requirements", requirements_id),
      plan: SpecWorkspace.read_artifact(repository, "plan", plan_id),
      decisions: read_decisions(repository, milestone)
    }
  end

  defp read_decisions(repository, milestone) do
    milestone
    |> list_metadata("decisions")
    |> Enum.map(&SpecWorkspace.read_artifact(repository, "decision", &1))
  end

  defp proposal_items(sources) do
    if detailed_plan?(sources.plan["body"]) do
      implementation_items(sources)
    else
      clarification_items(sources)
    end
  end

  defp implementation_items(sources) do
    milestone_id = sources.milestone["id"]
    title = sources.milestone["title"] || human_id(milestone_id)
    details = implementation_details(sources.plan["body"])
    related = source_artifact_lines(sources)

    [
      %{
        id: item_id(milestone_id, 1),
        title: "Prepare implementation boundaries for #{title}",
        priority: "medium",
        depends_on: [],
        goal: "Confirm the approved plan, source artifacts, and repository areas before code changes begin.",
        notes: take_lines(details, 0, 4),
        acceptance: [
          "Source milestone, requirements, plan, and decisions are reviewed before implementation.",
          "Affected files and areas are clear enough for the next tasks.",
          "No task starts Coding Assistant work automatically."
        ],
        review_expectations: [
          "Reviewer can trace the task back to the approved milestone.",
          "Task scope stays within the approved plan."
        ],
        related: related
      },
      %{
        id: item_id(milestone_id, 2),
        title: "Implement service changes for #{title}",
        priority: "medium",
        depends_on: [item_id(milestone_id, 1)],
        goal: "Add or update the backend behavior described by the approved implementation plan.",
        notes: section_lines(sources.plan["body"], ["API changes", "Data model changes"]),
        acceptance: [
          "Service behavior follows the approved requirements.",
          "New or changed APIs are covered by backend tests.",
          "Existing task lifecycle behavior remains intact."
        ],
        review_expectations: [
          "Reviewer can verify service behavior from tests and source artifacts.",
          "No unrelated service refactors are included."
        ],
        related: related
      },
      %{
        id: item_id(milestone_id, 3),
        title: "Implement workspace UI changes for #{title}",
        priority: "medium",
        depends_on: [item_id(milestone_id, 1), item_id(milestone_id, 2)],
        goal: "Expose the approved plan behavior in the workspace UI without starting execution automatically.",
        notes: section_lines(sources.plan["body"], ["UI changes", "Files and areas likely affected"]),
        acceptance: [
          "Workspace users can complete the planned workflow.",
          "Linked artifacts remain visible and editable.",
          "Task creation and Coding Assistant assignment stay separate user actions."
        ],
        review_expectations: [
          "Reviewer can use the workflow from the workspace dashboard.",
          "UI copy uses plain product language."
        ],
        related: related
      },
      %{
        id: item_id(milestone_id, 4),
        title: "Add validation coverage for #{title}",
        priority: "medium",
        depends_on: [item_id(milestone_id, 2), item_id(milestone_id, 3)],
        goal: "Cover the implemented behavior with backend tests, type checks, build validation, and focused smoke checks.",
        notes: section_lines(sources.plan["body"], ["Validation plan", "Risks"]),
        acceptance: [
          "Backend tests cover the new workflow.",
          "Frontend type checks and build pass.",
          "Smoke checks prove generated tasks appear in the task board as To-do."
        ],
        review_expectations: [
          "Reviewer can see validation commands and outcomes.",
          "Known limitations are documented."
        ],
        related: related
      },
      %{
        id: item_id(milestone_id, 5),
        title: "Document #{title} completion notes",
        priority: "low",
        depends_on: [item_id(milestone_id, 4)],
        goal: "Record what changed, what was validated, and what remains out of scope.",
        notes: ["Update milestone implementation notes and user-facing docs."],
        acceptance: [
          "Documentation lists artifacts, APIs, UI changes, tests, and smoke checks.",
          "Non-goals are explicit.",
          "Later work is described without implementing it."
        ],
        review_expectations: [
          "Reviewer can understand the milestone handoff from Markdown alone.",
          "Documentation matches the actual implementation."
        ],
        related: related
      }
    ]
  end

  defp clarification_items(sources) do
    milestone_id = sources.milestone["id"]
    title = sources.milestone["title"] || human_id(milestone_id)
    related = source_artifact_lines(sources)

    [
      %{
        id: item_id(milestone_id, 1),
        title: "Clarify implementation scope for #{title}",
        priority: "medium",
        depends_on: [],
        goal: "Turn the approved but underspecified plan into concrete implementation boundaries.",
        notes: [
          "Review the milestone discussion and requirements.",
          "Write down the behavior that must be implemented before coding begins."
        ],
        acceptance: [
          "Open implementation questions are listed.",
          "The next implementation tasks can be scoped without guessing."
        ],
        review_expectations: [
          "Reviewer can see which details were missing from the approved plan."
        ],
        related: related
      },
      %{
        id: item_id(milestone_id, 2),
        title: "Identify affected code areas for #{title}",
        priority: "medium",
        depends_on: [item_id(milestone_id, 1)],
        goal: "Map the likely service, API, UI, and test areas before implementation tasks are created.",
        notes: [
          "Inspect current repository routes, service modules, and workspace components.",
          "Keep findings linked to the approved plan."
        ],
        acceptance: [
          "Likely affected files and areas are recorded.",
          "Unknown areas are marked as questions instead of assumptions."
        ],
        review_expectations: [
          "Reviewer can trace affected areas back to source artifacts."
        ],
        related: related
      },
      %{
        id: item_id(milestone_id, 3),
        title: "Define validation plan for #{title}",
        priority: "low",
        depends_on: [item_id(milestone_id, 2)],
        goal: "Create a concrete validation checklist for the later implementation tasks.",
        notes: [
          "Use the requirements acceptance criteria as the starting point.",
          "Include backend, frontend, and smoke checks where relevant."
        ],
        acceptance: [
          "Validation commands and smoke checks are listed.",
          "The plan avoids starting Coding Assistant work automatically."
        ],
        review_expectations: [
          "Reviewer can tell what will prove implementation completion."
        ],
        related: related
      }
    ]
  end

  defp proposal_body(sources, items, created_tasks) do
    created =
      case created_tasks do
        [] -> "No task files have been created from this proposal yet."
        keys -> Enum.map_join(keys, "\n", &"- #{&1}")
      end

    """
    # #{human_id(sources.milestone["id"])} Task Proposal

    ## Summary

    Clarise proposed implementation tasks from the approved milestone plan.

    ## Generation

    Generation id: #{generation_id(sources.milestone["id"])}
    Source milestone: #{sources.milestone["id"]}
    Source requirements: #{sources.requirements["id"]}
    Source plan: #{sources.plan["id"]}

    ## Proposed tasks

    #{Enum.map_join(items, "\n\n", &proposal_item_body/1)}

    ## Created tasks

    #{created}

    ## Related artifacts

    #{Enum.join(source_artifact_lines(sources), "\n")}
    """
  end

  defp proposal_item_body(item) do
    depends_on = if item.depends_on == [], do: "none", else: Enum.join(item.depends_on, ", ")

    """
    ### #{item.id} - #{item.title}

    Priority: #{item.priority}
    Depends on: #{depends_on}

    Goal: #{item.goal}

    Implementation notes:
    #{markdown_list(item.notes)}

    Acceptance criteria:
    #{markdown_list(item.acceptance)}

    Review expectations:
    #{markdown_list(item.review_expectations)}
    """
    |> String.trim()
  end

  defp task_body(item, sources) do
    """
    # #{item.title}

    ## Goal

    #{item.goal}

    ## Context from milestone

    #{fallback(section(sources.milestone["body"], "Goal"), "Review #{sources.milestone["id"]} before implementation.")}

    ## Implementation notes

    #{markdown_list(item.notes)}

    ## Acceptance criteria

    #{markdown_list(item.acceptance)}

    ## Review expectations

    #{markdown_list(item.review_expectations)}

    ## Related artifacts

    #{Enum.join(item.related, "\n")}
    """
  end

  defp detailed_plan?(body) do
    implementation_details(body) |> length() >= 4
  end

  defp implementation_details(body) do
    section_lines(body, [
      "Implementation phases",
      "Files and areas likely affected",
      "Data model changes",
      "API changes",
      "UI changes",
      "Validation plan"
    ])
  end

  defp section_lines(body, headings) do
    headings
    |> Enum.flat_map(fn heading ->
      body
      |> section(heading)
      |> lines_from_section()
    end)
    |> Enum.uniq()
  end

  defp lines_from_section(nil), do: []

  defp lines_from_section(section) do
    section
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.trim_leading(&1, "- "))
    |> Enum.map(&String.trim_leading(&1, "* "))
    |> Enum.map(&String.trim_leading(&1, "[ ] "))
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
  end

  defp section(body, heading) when is_binary(body) do
    pattern = ~r/^## #{Regex.escape(heading)}\s*\n(?<content>.*?)(?=^## |\z)/ms

    case Regex.named_captures(pattern, body) do
      %{"content" => content} ->
        content = String.trim(content)
        if content == "", do: nil, else: content

      _ ->
        nil
    end
  end

  defp section(_body, _heading), do: nil

  defp source_artifact_lines(sources) do
    [
      "- Milestone: #{sources.milestone["id"]}",
      "- Discussion: #{sources.discussion["id"]}",
      "- Requirements: #{sources.requirements["id"]}",
      "- Plan: #{sources.plan["id"]}"
    ] ++ Enum.map(sources.decisions, &"- Decision: #{&1["id"]}")
  end

  defp existing_generated_tasks(tasks, generation_id) do
    tasks
    |> Enum.flat_map(fn task ->
      frontmatter = Map.get(task, :frontmatter, %{})

      if frontmatter["generation_id"] == generation_id &&
           is_binary(frontmatter["proposal_item_id"]) do
        [{frontmatter["proposal_item_id"], task["key"]}]
      else
        []
      end
    end)
    |> Map.new()
  end

  defp resolve_dependencies(depends_on, mapping) do
    depends_on
    |> Enum.map(&Map.get(mapping, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp public_item(item) do
    %{
      "id" => item.id,
      "title" => item.title,
      "priority" => item.priority,
      "depends_on" => item.depends_on,
      "goal" => item.goal,
      "implementation_notes" => item.notes,
      "acceptance_criteria" => item.acceptance,
      "review_expectations" => item.review_expectations,
      "related_artifacts" => item.related
    }
  end

  defp public_task(nil), do: nil

  defp public_task(task) do
    Map.drop(task, [:repository, :file_path, :frontmatter, :body])
  end

  defp task_board_payload(source_milestone, created_tasks) do
    %{
      "sourceMilestone" => source_milestone,
      "createdTasks" => created_tasks
    }
  end

  defp metadata_id!(artifact, key, message) do
    case get_in(artifact, ["metadata", key]) do
      value when is_binary(value) and value != "" -> value
      _ -> raise ArgumentError, message
    end
  end

  defp list_metadata(artifact, key) do
    artifact
    |> get_in(["metadata", key])
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp read_existing_proposal(repository, proposal_id) do
    if Store.artifact_exists?(repository, "task_proposal", proposal_id) do
      SpecWorkspace.read_artifact(repository, "task_proposal", proposal_id)
    end
  end

  defp proposal_id(milestone_id), do: "#{milestone_id}-task-proposal"
  defp generation_id(milestone_id), do: "#{milestone_id}-plan-to-task-v1"
  defp item_id(milestone_id, number), do: "#{milestone_id}-task-#{pad(number)}"
  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(3, "0")

  defp take_lines(lines, start, count) do
    lines
    |> Enum.slice(start, count)
    |> case do
      [] -> ["Review the approved plan and confirm implementation boundaries."]
      selected -> selected
    end
  end

  defp markdown_list(items) do
    items
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> "- Not recorded."
      values -> Enum.map_join(values, "\n", &"- #{&1}")
    end
  end

  defp fallback(value, fallback) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: fallback, else: value
  end

  defp fallback(_value, fallback), do: fallback

  defp human_id("milestone-" <> number), do: "Milestone #{number}"
  defp human_id(id), do: id

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_), do: false
end
