defmodule SymphoniaService.Clarise.PlanToTaskCompiler do
  @moduledoc """
  Deterministic Clarise bridge from an approved milestone plan to task files.
  """

  alias SymphoniaService.Readiness.RepositoryReadiness
  alias SymphoniaService.SpecWorkspace.Store
  alias SymphoniaService.{SpecWorkspace, TaskStore}

  @generated_by "clarise_plan_to_task"
  @generation_version "v2"
  @legacy_generation_versions ["v1"]
  @priorities ~w(urgent high medium low no-priority)

  def propose(repository, milestone_id, payload \\ %{}) do
    SpecWorkspace.initialize(repository)
    sources = load_sources(repository, milestone_id)
    proposal_id = proposal_id(milestone_id)
    existing = read_existing_proposal(repository, proposal_id)
    regenerate? = truthy?(Map.get(payload, "regenerate"))

    items =
      case {regenerate?, proposal_items_from_artifact(existing, sources, repository)} do
        {false, [_first | _rest] = persisted_items} -> persisted_items
        _ -> generated_items(sources, repository)
      end

    created_tasks = list_metadata(existing, "created_tasks")
    readiness = readiness(repository)
    items = Enum.map(items, &put_item_readiness(&1, readiness))

    status =
      if existing && existing["status"] == "created" && !regenerate? do
        "created"
      else
        "draft"
      end

    proposal =
      write_proposal(repository, sources, items, status, created_tasks, readiness)

    response_payload(
      proposal,
      items,
      created_tasks,
      [],
      0,
      [],
      readiness["blockers"],
      readiness["warnings"],
      if(created_tasks == [], do: "review_task_proposal", else: "task_board"),
      sources
    )
  end

  def create_tasks(registry_path, repository, milestone_id, payload \\ %{}) do
    SpecWorkspace.initialize(repository)
    sources = load_sources(repository, milestone_id)
    proposal_id = proposal_id(milestone_id)
    existing = read_existing_proposal(repository, proposal_id)

    unless existing do
      raise ArgumentError, "Task proposal is required before creating tasks."
    end

    items =
      existing
      |> proposal_items_from_artifact(sources, repository)
      |> case do
        [] -> generated_items(sources, repository)
        persisted_items -> persisted_items
      end
      |> merge_payload_items(payload, sources, repository)

    selected_ids = selected_item_ids(items, payload)

    items =
      Enum.map(items, fn item ->
        Map.put(item, :selected, item.id in selected_ids)
      end)

    readiness = readiness(repository)
    items = Enum.map(items, &put_item_readiness(&1, readiness))
    tasks = TaskStore.list_tasks(repository)
    initial_mapping = existing_generated_tasks(tasks, sources.milestone["id"])
    task_keys = tasks |> Enum.map(& &1["key"]) |> MapSet.new()

    with :ok <- ensure_items_selected(selected_ids),
         {:ok, selected_items} <-
           selected_items_in_dependency_order(items, selected_ids, initial_mapping, task_keys) do
      {mapping, result_tasks, created_count, skipped} =
        Enum.reduce(selected_items, {initial_mapping, [], 0, []}, fn item,
                                                                     {mapping, tasks, count,
                                                                      skipped} ->
          case Map.get(mapping, item.id) do
            nil ->
              depends_on = resolve_dependencies(item.depends_on, mapping, task_keys)

              task =
                TaskStore.create_task(registry_path, repository, %{
                  "title" => item.title,
                  "description" => body_for_item(item, sources),
                  "priority" => item.priority,
                  "project" => sources.milestone["id"],
                  "type" => "task",
                  "source_milestone" => sources.milestone["id"],
                  "source_plan" => sources.plan["id"],
                  "source_requirements" => sources.requirements["id"],
                  "source_discussion" => sources.discussion["id"],
                  "source_decisions" => Enum.map(sources.decisions, & &1["id"]),
                  "generated_by" => @generated_by,
                  "generation_id" => generation_id(sources.milestone["id"]),
                  "proposal_item_id" => item.id,
                  "depends_on" => depends_on,
                  "review_expectations" => item.review_expectations
                })

              {
                Map.put(mapping, item.id, task["key"]),
                tasks ++ [task],
                count + 1,
                skipped
              }

            key ->
              task = TaskStore.get_task(repository, key)

              {
                mapping,
                tasks ++ List.wrap(task),
                count,
                skipped ++ [%{"title" => item.title, "reason" => "Task already exists."}]
              }
          end
        end)

      created_tasks = created_tasks_from_mapping(items, mapping)

      proposal =
        write_proposal(repository, sources, items, "created", created_tasks, readiness)

      response_payload(
        proposal,
        items,
        created_tasks,
        result_tasks,
        created_count,
        skipped,
        readiness["blockers"],
        readiness["warnings"],
        "task_board",
        sources
      )
    else
      {:error, blockers} ->
        readiness = Map.update!(readiness, "blockers", &Enum.uniq(&1 ++ blockers))
        created_tasks = list_metadata(existing, "created_tasks")
        proposal = write_proposal(repository, sources, items, "draft", created_tasks, readiness)

        response_payload(
          proposal,
          items,
          created_tasks,
          [],
          0,
          [],
          readiness["blockers"],
          readiness["warnings"],
          "resolve_dependencies",
          sources
        )
    end
  end

  defp load_sources(repository, milestone_id) do
    milestone = SpecWorkspace.read_artifact(repository, "milestone", milestone_id)

    unless milestone["status"] == "approved" do
      raise ArgumentError, "Milestone must be approved before generating tasks."
    end

    discussion_id = metadata_id!(milestone, "discussion", "Discussion artifact is required.")

    requirements_id =
      metadata_id!(milestone, "requirements", "Requirements artifact is required.")

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

  defp generated_items(sources, repository) do
    sources
    |> proposal_items()
    |> Enum.map(&complete_item(&1, sources, repository))
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
        selected: true,
        title: "Prepare implementation boundaries for #{title}",
        priority: "medium",
        depends_on: [],
        goal:
          "Confirm the approved plan, source artifacts, and repository areas before code changes begin.",
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
        linked_files: [],
        related: related
      },
      %{
        id: item_id(milestone_id, 2),
        selected: true,
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
        linked_files: [],
        related: related
      },
      %{
        id: item_id(milestone_id, 3),
        selected: true,
        title: "Implement workspace UI changes for #{title}",
        priority: "medium",
        depends_on: [item_id(milestone_id, 1), item_id(milestone_id, 2)],
        goal:
          "Expose the approved plan behavior in the workspace UI without starting execution automatically.",
        notes:
          section_lines(sources.plan["body"], ["UI changes", "Files and areas likely affected"]),
        acceptance: [
          "Workspace users can complete the planned workflow.",
          "Linked artifacts remain visible and editable.",
          "Task creation and Coding Assistant assignment stay separate user actions."
        ],
        review_expectations: [
          "Reviewer can use the workflow from the workspace dashboard.",
          "UI copy uses plain product language."
        ],
        linked_files: [],
        related: related
      },
      %{
        id: item_id(milestone_id, 4),
        selected: true,
        title: "Add validation coverage for #{title}",
        priority: "medium",
        depends_on: [item_id(milestone_id, 2), item_id(milestone_id, 3)],
        goal:
          "Cover the implemented behavior with backend tests, type checks, build validation, and focused smoke checks.",
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
        linked_files: [],
        related: related
      },
      %{
        id: item_id(milestone_id, 5),
        selected: true,
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
        linked_files: [],
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
        selected: true,
        title: "Clarify implementation scope for #{title}",
        priority: "medium",
        depends_on: [],
        goal:
          "Turn the approved but underspecified plan into concrete implementation boundaries.",
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
        linked_files: [],
        related: related
      },
      %{
        id: item_id(milestone_id, 2),
        selected: true,
        title: "Identify affected code areas for #{title}",
        priority: "medium",
        depends_on: [item_id(milestone_id, 1)],
        goal:
          "Map the likely service, API, UI, and test areas before implementation tasks are created.",
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
        linked_files: [],
        related: related
      },
      %{
        id: item_id(milestone_id, 3),
        selected: true,
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
        linked_files: [],
        related: related
      }
    ]
  end

  defp complete_item(item, sources, repository) do
    item =
      %{
        id: string_field(item, :id) || string_field(item, "id"),
        selected: boolean_field(item, :selected, boolean_field(item, "selected", true)),
        title: string_field(item, :title) || string_field(item, "title"),
        priority: priority_field(item, :priority, priority_field(item, "priority")),
        depends_on: list_field(item, :depends_on) ++ list_field(item, "depends_on"),
        goal: string_field(item, :goal) || string_field(item, "goal"),
        notes:
          list_field(item, :notes) ++
            list_field(item, "notes") ++ list_field(item, "implementation_notes"),
        acceptance:
          list_field(item, :acceptance) ++
            list_field(item, "acceptance") ++ list_field(item, "acceptance_criteria"),
        review_expectations:
          list_field(item, :review_expectations) ++ list_field(item, "review_expectations"),
        linked_files:
          safe_paths(list_field(item, :linked_files) ++ list_field(item, "linked_files")),
        related: list_field(item, :related) ++ list_field(item, "related_artifacts"),
        body: string_field(item, :body) || string_field(item, "body"),
        automation_readiness:
          map_field(item, :automation_readiness) || map_field(item, "automation_readiness")
      }
      |> normalize_item_lists()

    item =
      item
      |> Map.put(
        :related,
        if(item.related == [], do: source_artifact_lines(sources), else: item.related)
      )
      |> Map.put(:linked_files, safe_paths(item.linked_files))
      |> Map.put(
        :automation_readiness,
        item.automation_readiness || readiness(repository)
      )

    Map.put(item, :body, body_for_item(item, sources))
  end

  defp normalize_item_lists(item) do
    item
    |> Map.put(:depends_on, clean_dependency_ids(item.depends_on))
    |> Map.put(:notes, clean_list(item.notes))
    |> Map.put(:acceptance, clean_list(item.acceptance))
    |> Map.put(:review_expectations, clean_list(item.review_expectations))
    |> Map.put(:related, clean_list(item.related))
  end

  defp merge_payload_items(items, payload, sources, repository) do
    overrides =
      payload
      |> Map.get("items", Map.get(payload, "proposalItems", []))
      |> List.wrap()
      |> Enum.filter(&is_map/1)
      |> Map.new(fn item -> {string_field(item, "id") || "", item} end)

    Enum.map(items, fn item ->
      case Map.get(overrides, item.id) do
        nil ->
          item

        override ->
          override =
            override
            |> Enum.map(fn {key, value} -> {to_string(key), value} end)
            |> Map.new()

          body_override = payload_body_override(item, override)

          merged =
            item
            |> maybe_override(:selected, boolean_field(override, "selected", item.selected))
            |> maybe_override(:title, string_field(override, "title"))
            |> maybe_override(:priority, priority_field(override, "priority"))
            |> maybe_override(:depends_on, dependency_override(override))
            |> maybe_override(:goal, string_field(override, "goal"))
            |> maybe_override(:notes, list_override(override, "implementation_notes"))
            |> maybe_override(:acceptance, list_override(override, "acceptance_criteria"))
            |> maybe_override(
              :review_expectations,
              list_override(override, "review_expectations")
            )
            |> maybe_override(:linked_files, safe_paths(list_override(override, "linked_files")))
            |> maybe_override(:body, body_override)

          if body_override do
            complete_item(merged, sources, repository)
          else
            complete_item(Map.delete(merged, :body), sources, repository)
          end
      end
    end)
  end

  defp proposal_items_from_artifact(nil, _sources, _repository), do: []

  defp proposal_items_from_artifact(artifact, sources, repository) do
    artifact
    |> get_in(["metadata", "proposal_items"])
    |> case do
      values when is_list(values) -> values
      _ -> []
    end
    |> Enum.filter(&is_map/1)
    |> Enum.map(&complete_item(&1, sources, repository))
    |> Enum.reject(&blank?(&1.id))
  end

  defp selected_item_ids(items, payload) do
    explicit =
      Map.get(payload, "selectedProposalItemIds") ||
        Map.get(payload, "selected_proposal_item_ids")

    valid_ids = items |> Enum.map(& &1.id) |> MapSet.new()

    case explicit do
      values when is_list(values) ->
        values
        |> clean_dependency_ids()
        |> Enum.filter(&MapSet.member?(valid_ids, &1))

      _ ->
        items
        |> Enum.filter(& &1.selected)
        |> Enum.map(& &1.id)
    end
  end

  defp ensure_items_selected([]),
    do: {:error, ["Select at least one proposal item before creating tasks."]}

  defp ensure_items_selected(_selected_ids), do: :ok

  defp selected_items_in_dependency_order(items, selected_ids, mapping, task_keys) do
    by_id = Map.new(items, &{&1.id, &1})
    selected = MapSet.new(selected_ids)

    {ordered_ids, _visited, blockers} =
      Enum.reduce(selected_ids, {[], MapSet.new(), []}, fn id, {ordered, visited, blockers} ->
        {ordered, visited, item_blockers} =
          visit_item(id, by_id, selected, mapping, task_keys, ordered, visited, MapSet.new())

        {ordered, visited, blockers ++ item_blockers}
      end)

    blockers = Enum.uniq(blockers)

    if blockers == [] do
      {:ok, Enum.map(ordered_ids, &Map.fetch!(by_id, &1))}
    else
      {:error, blockers}
    end
  end

  defp visit_item(id, by_id, selected, mapping, task_keys, ordered, visited, visiting) do
    cond do
      MapSet.member?(visited, id) ->
        {ordered, visited, []}

      MapSet.member?(visiting, id) ->
        {ordered, visited, ["Dependency cycle includes #{id}."]}

      is_nil(Map.get(by_id, id)) ->
        {ordered, visited, ["Selected proposal item #{id} does not exist."]}

      true ->
        item = Map.fetch!(by_id, id)
        visiting = MapSet.put(visiting, id)

        {ordered, visited, blockers} =
          Enum.reduce(item.depends_on, {ordered, visited, []}, fn dependency,
                                                                  {ordered, visited, blockers} ->
            cond do
              Map.has_key?(mapping, dependency) or MapSet.member?(task_keys, dependency) ->
                {ordered, visited, blockers}

              MapSet.member?(selected, dependency) ->
                {next_ordered, next_visited, next_blockers} =
                  visit_item(
                    dependency,
                    by_id,
                    selected,
                    mapping,
                    task_keys,
                    ordered,
                    visited,
                    visiting
                  )

                {next_ordered, next_visited, blockers ++ next_blockers}

              true ->
                {
                  ordered,
                  visited,
                  blockers ++
                    [
                      "Dependency #{dependency} for #{item.id} is not selected or already created."
                    ]
                }
            end
          end)

        if id in ordered do
          {ordered, visited, blockers}
        else
          {ordered ++ [id], MapSet.put(visited, id), blockers}
        end
    end
  end

  defp write_proposal(repository, sources, items, status, created_tasks, readiness) do
    Store.create_or_update_artifact(
      repository,
      "task_proposal",
      proposal_id(sources.milestone["id"]),
      %{
        "title" => "#{sources.milestone["title"]} task proposal",
        "status" => status,
        "source_milestone" => sources.milestone["id"],
        "source_plan" => sources.plan["id"],
        "source_requirements" => sources.requirements["id"],
        "source_discussion" => sources.discussion["id"],
        "source_decisions" => Enum.map(sources.decisions, & &1["id"]),
        "generated_by" => @generated_by,
        "generation_id" => generation_id(sources.milestone["id"]),
        "proposal_items" => Enum.map(items, &item_metadata/1),
        "blockers" => readiness["blockers"],
        "warnings" => readiness["warnings"],
        "readiness_labels" =>
          Map.merge(readiness["labels"] || %{}, sources_readiness_labels(sources)),
        "created_tasks" => created_tasks,
        "body" => proposal_body(sources, items, created_tasks, readiness)
      }
    )
  end

  defp response_payload(
         proposal,
         items,
         created_tasks,
         tasks,
         created_count,
         skipped,
         blockers,
         warnings,
         next_step,
         sources
       ) do
    %{
      "proposal" => proposal,
      "items" => Enum.map(items, &public_item/1),
      "tasks" => Enum.map(tasks, &public_task/1),
      "createdTasks" => created_tasks,
      "createdCount" => created_count,
      "skipped" => skipped,
      "generationId" => generation_id(sources.milestone["id"]),
      "blockers" => blockers,
      "warnings" => warnings,
      "automationReadiness" => %{
        "ready" => blockers == [],
        "blockers" => blockers,
        "warnings" => warnings,
        "labels" =>
          Map.merge(
            sources_readiness_labels(sources),
            readiness_labels_from_items(items)
          )
      },
      "nextStep" => next_step,
      "taskBoard" => task_board_payload(sources.milestone["id"], created_tasks)
    }
  end

  defp proposal_body(sources, items, created_tasks, readiness) do
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
    Source discussion: #{sources.discussion["id"]}
    Source requirements: #{sources.requirements["id"]}
    Source plan: #{sources.plan["id"]}

    ## Proposed tasks

    #{Enum.map_join(items, "\n\n", &proposal_item_body/1)}

    ## Harness readiness

    #{readiness_markdown(readiness)}

    ## Created tasks

    #{created}

    ## Related artifacts

    #{Enum.join(source_artifact_lines(sources), "\n")}
    """
  end

  defp sources_readiness_labels(sources) do
    %{
      "sourceMilestoneApproved" =>
        sources.milestone["status"] == "approved" or
          get_in(sources.milestone, ["metadata", "status"]) == "approved",
      "dependenciesComplete" => true
    }
  end

  defp readiness_labels_from_items(items) do
    items
    |> Enum.map(& &1.automation_readiness)
    |> Enum.find(&is_map/1)
    |> case do
      %{"labels" => labels} when is_map(labels) -> labels
      _ -> %{}
    end
  end

  defp proposal_item_body(item) do
    depends_on = if item.depends_on == [], do: "none", else: Enum.join(item.depends_on, ", ")
    selected = if item.selected, do: "yes", else: "no"

    """
    ### #{item.id} - #{item.title}

    Selected: #{selected}
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

  defp body_for_item(item, sources) do
    body =
      case item.body do
        value when is_binary(value) and value != "" ->
          if String.starts_with?(String.trim_leading(value), "#") do
            value
          else
            "# #{item.title}\n\n#{value}"
          end

        _ ->
          task_body(item, sources)
      end

    String.trim_trailing(body)
  end

  defp readiness(repository) do
    RepositoryReadiness.compiler_readiness(repository)
  end

  defp put_item_readiness(item, readiness) do
    Map.put(item, :automation_readiness, readiness)
  end

  defp readiness_markdown(%{"blockers" => [], "warnings" => []}) do
    """
    Repository ready: yes
    GitHub linked: yes
    Validation configured: yes

    Ready: no obvious blockers found. Harness eligibility remains authoritative after task creation.
    """
    |> String.trim()
  end

  defp readiness_markdown(readiness) do
    labels = readiness["labels"] || %{}

    blockers =
      case readiness["blockers"] do
        [] -> "- None."
        values -> markdown_list(values)
      end

    warnings =
      case readiness["warnings"] do
        [] -> "- None."
        values -> markdown_list(values)
      end

    """
    Repository ready: #{yes_no(labels["repositoryReady"])}
    GitHub linked: #{yes_no(labels["githubLinked"])}
    Automation enabled: #{yes_no(labels["automationEnabled"])}
    Validation configured: #{yes_no(labels["validationConfigured"])}

    Blockers:
    #{blockers}

    Warnings:
    #{warnings}

    Harness eligibility remains authoritative after task creation.
    """
    |> String.trim()
  end

  defp yes_no(true), do: "yes"
  defp yes_no(false), do: "no"
  defp yes_no(_value), do: "unknown"

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

  defp existing_generated_tasks(tasks, milestone_id) do
    generation_ids = generation_ids(milestone_id)

    tasks
    |> Enum.flat_map(fn task ->
      frontmatter = Map.get(task, :frontmatter, %{})

      if frontmatter["generated_by"] == @generated_by &&
           frontmatter["source_milestone"] == milestone_id &&
           frontmatter["generation_id"] in generation_ids &&
           is_binary(frontmatter["proposal_item_id"]) do
        [{frontmatter["proposal_item_id"], task["key"]}]
      else
        []
      end
    end)
    |> Map.new()
  end

  defp resolve_dependencies(depends_on, mapping, task_keys) do
    depends_on
    |> Enum.map(fn dependency -> Map.get(mapping, dependency) || dependency end)
    |> Enum.filter(
      &(MapSet.member?(task_keys, &1) or String.match?(&1, ~r/^[A-Z][A-Z0-9]*-\d+$/))
    )
    |> Enum.uniq()
  end

  defp created_tasks_from_mapping(items, mapping) do
    items
    |> Enum.map(&Map.get(mapping, &1.id))
    |> Enum.reject(&is_nil/1)
  end

  defp public_item(item) do
    %{
      "id" => item.id,
      "selected" => item.selected,
      "title" => item.title,
      "body" => item.body,
      "priority" => item.priority,
      "depends_on" => item.depends_on,
      "goal" => item.goal,
      "implementation_notes" => item.notes,
      "acceptance_criteria" => item.acceptance,
      "review_expectations" => item.review_expectations,
      "related_artifacts" => item.related,
      "linked_files" => item.linked_files,
      "automation_readiness" => item.automation_readiness
    }
  end

  defp item_metadata(item) do
    %{
      "id" => item.id,
      "selected" => item.selected,
      "title" => item.title,
      "body" => item.body,
      "priority" => item.priority,
      "depends_on" => item.depends_on,
      "goal" => item.goal,
      "implementation_notes" => item.notes,
      "acceptance_criteria" => item.acceptance,
      "review_expectations" => item.review_expectations,
      "related_artifacts" => item.related,
      "linked_files" => item.linked_files,
      "automation_readiness" => item.automation_readiness
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

  defp list_metadata(nil, _key), do: []

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

  defp maybe_override(item, _key, nil), do: item
  defp maybe_override(item, key, value), do: Map.put(item, key, value)

  defp string_field(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: nil, else: value

      _ ->
        nil
    end
  end

  defp string_field(_map, _key), do: nil

  defp boolean_field(map, key, default) when is_map(map) do
    case Map.get(map, key) do
      value when is_boolean(value) -> value
      "true" -> true
      "false" -> false
      _ -> default
    end
  end

  defp boolean_field(_map, _key, default), do: default

  defp priority_field(map, key, default \\ "medium") do
    case string_field(map, key) do
      value when value in @priorities -> value
      _ -> default
    end
  end

  defp payload_body_override(item, override) do
    body = string_field(override, "body")

    changed_without_body? =
      Enum.any?(
        [
          "title",
          "priority",
          "depends_on",
          "dependsOn",
          "goal",
          "implementation_notes",
          "implementationNotes",
          "acceptance_criteria",
          "acceptanceCriteria",
          "review_expectations",
          "reviewExpectations",
          "linked_files",
          "linkedFiles"
        ],
        &Map.has_key?(override, &1)
      )

    cond do
      is_nil(body) ->
        nil

      changed_without_body? && body == item.body ->
        nil

      true ->
        body
    end
  end

  defp dependency_override(map) do
    value = Map.get(map, "depends_on", Map.get(map, "dependsOn"))
    if is_nil(value), do: nil, else: clean_dependency_ids(value)
  end

  defp list_override(map, key) do
    camel = camel_key(key)
    value = Map.get(map, key, Map.get(map, camel))
    if is_nil(value), do: nil, else: clean_list(value)
  end

  defp list_field(map, key) when is_map(map) do
    map
    |> Map.get(key, [])
    |> clean_list()
  end

  defp list_field(_map, _key), do: []

  defp map_field(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_map(value) -> value
      _ -> nil
    end
  end

  defp map_field(_map, _key), do: nil

  defp clean_dependency_ids(value) when is_binary(value) do
    value
    |> String.split([",", "\n"])
    |> clean_dependency_ids()
  end

  defp clean_dependency_ids(values) do
    values
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.downcase(&1) == "none"))
    |> Enum.uniq()
  end

  defp clean_list(value) when is_binary(value) do
    value
    |> String.split("\n")
    |> clean_list()
  end

  defp clean_list(values) do
    values
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp safe_paths(values) do
    values
    |> clean_list()
    |> Enum.reject(&(String.starts_with?(&1, "/") or String.contains?(&1, "..")))
  end

  defp camel_key("acceptance_criteria"), do: "acceptanceCriteria"
  defp camel_key("review_expectations"), do: "reviewExpectations"
  defp camel_key("implementation_notes"), do: "implementationNotes"
  defp camel_key("linked_files"), do: "linkedFiles"
  defp camel_key(key), do: key

  defp proposal_id(milestone_id), do: "#{milestone_id}-task-proposal"
  defp generation_id(milestone_id), do: "#{milestone_id}-plan-to-task-#{@generation_version}"

  defp generation_ids(milestone_id) do
    [@generation_version | @legacy_generation_versions]
    |> Enum.map(&"#{milestone_id}-plan-to-task-#{&1}")
  end

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

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")

  defp human_id("milestone-" <> number), do: "Milestone #{number}"
  defp human_id(id), do: id

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_), do: false
end
