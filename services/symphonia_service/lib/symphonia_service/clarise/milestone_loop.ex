defmodule SymphoniaService.Clarise.MilestoneLoop do
  @moduledoc """
  Clarise workflow for establishing milestone spec artifacts.
  """

  alias SymphoniaService.Clarise.{
    DecisionRecorder,
    MilestoneDiscussion,
    PlanBuilder,
    RequirementsBuilder
  }

  alias SymphoniaService.SpecWorkspace
  alias SymphoniaService.SpecWorkspace.Store

  def questions, do: MilestoneDiscussion.questions()

  def start(repository, attrs \\ %{}) do
    SpecWorkspace.initialize(repository)

    id = Store.next_id(repository, "milestone")
    title = string_attr(attrs, "title") || "Untitled milestone"
    goal = string_attr(attrs, "goal") || ""

    milestone =
      Store.create_artifact(repository, "milestone", id, %{
        "title" => title,
        "status" => "draft",
        "discussion" => linked_id(id, "discussion"),
        "requirements" => linked_id(id, "requirements"),
        "plan" => linked_id(id, "plan"),
        "decisions" => [],
        "body" => milestone_body(id, title, goal)
      })

    %{"milestone" => milestone, "questions" => questions_payload(), "nextStep" => "discuss"}
  end

  def discuss(repository, milestone_id, payload) do
    milestone = read_milestone(repository, milestone_id)
    title = string_attr(payload, "title") || milestone["title"]
    goal = string_attr(payload, "goal")
    discussion_id = metadata_id(milestone, "discussion", linked_id(milestone["id"], "discussion"))

    milestone_body =
      milestone["body"]
      |> put_heading_title(milestone["id"], title)
      |> put_section("Goal", goal)

    milestone =
      SpecWorkspace.update_artifact(repository, "milestone", milestone["id"], %{
        "metadata" => %{
          "title" => title,
          "status" => "in_discussion",
          "discussion" => discussion_id,
          "requirements" =>
            metadata_id(milestone, "requirements", linked_id(milestone["id"], "requirements")),
          "plan" => metadata_id(milestone, "plan", linked_id(milestone["id"], "plan"))
        },
        "body" => milestone_body
      })

    discussion =
      Store.create_or_update_artifact(repository, "discussion", discussion_id, %{
        "title" => "#{title} discussion",
        "status" => "in_discussion",
        "related_milestone" => milestone["id"],
        "body" => MilestoneDiscussion.body(milestone, payload)
      })

    %{
      "milestone" => milestone,
      "discussion" => discussion,
      "questions" => questions_payload(),
      "nextStep" => "requirements"
    }
  end

  def requirements(repository, milestone_id, _payload \\ %{}) do
    milestone = read_milestone(repository, milestone_id)
    discussion_id = metadata_id(milestone, "discussion", linked_id(milestone["id"], "discussion"))
    discussion = require_artifact!(repository, "discussion", discussion_id, "Discussion artifact is required.")
    requirements_id = metadata_id(milestone, "requirements", linked_id(milestone["id"], "requirements"))

    requirements =
      Store.create_or_update_artifact(repository, "requirements", requirements_id, %{
        "title" => "#{milestone["title"]} requirements",
        "status" => "requirements_ready",
        "related_milestone" => milestone["id"],
        "body" => RequirementsBuilder.body(milestone, discussion)
      })

    milestone =
      SpecWorkspace.update_artifact(repository, "milestone", milestone["id"], %{
        "metadata" => %{"status" => "requirements_ready", "requirements" => requirements_id}
      })

    %{"milestone" => milestone, "requirements" => requirements, "nextStep" => "plan"}
  end

  def plan(repository, milestone_id, _payload \\ %{}) do
    milestone = read_milestone(repository, milestone_id)
    requirements_id = metadata_id(milestone, "requirements", linked_id(milestone["id"], "requirements"))
    requirements = require_artifact!(repository, "requirements", requirements_id, "Requirements artifact is required.")
    plan_id = metadata_id(milestone, "plan", linked_id(milestone["id"], "plan"))

    plan =
      Store.create_or_update_artifact(repository, "plan", plan_id, %{
        "title" => "#{milestone["title"]} plan",
        "status" => "plan_ready",
        "related_milestone" => milestone["id"],
        "body" => PlanBuilder.body(milestone, requirements)
      })

    milestone =
      SpecWorkspace.update_artifact(repository, "milestone", milestone["id"], %{
        "metadata" => %{"status" => "plan_ready", "plan" => plan_id}
      })

    %{"milestone" => milestone, "plan" => plan, "nextStep" => "approve"}
  end

  def decision(repository, milestone_id, payload) do
    milestone = read_milestone(repository, milestone_id)
    DecisionRecorder.create(repository, milestone, payload)
  end

  def approve(repository, milestone_id, _payload \\ %{}) do
    milestone = read_milestone(repository, milestone_id)
    discussion_id = metadata_id(milestone, "discussion", linked_id(milestone["id"], "discussion"))
    requirements_id = metadata_id(milestone, "requirements", linked_id(milestone["id"], "requirements"))
    plan_id = metadata_id(milestone, "plan", linked_id(milestone["id"], "plan"))

    require_artifact!(repository, "discussion", discussion_id, "Discussion artifact is required.")
    require_artifact!(repository, "requirements", requirements_id, "Requirements artifact is required.")
    require_artifact!(repository, "plan", plan_id, "Plan artifact is required.")

    approved_at = now()

    milestone =
      SpecWorkspace.update_artifact(repository, "milestone", milestone["id"], %{
        "metadata" => %{"status" => "approved", "approved_at" => approved_at},
        "body" => append_approval(milestone["body"], approved_at, discussion_id, requirements_id, plan_id)
      })

    %{"milestone" => milestone, "approved" => true}
  end

  defp read_milestone(repository, id), do: SpecWorkspace.read_artifact(repository, "milestone", id)

  defp require_artifact!(repository, type, id, message) do
    if Store.artifact_exists?(repository, type, id) do
      SpecWorkspace.read_artifact(repository, type, id)
    else
      raise ArgumentError, message
    end
  end

  defp milestone_body(id, title, goal) do
    number = suffix_number(id)

    """
    # Milestone #{number} - #{title}

    ## Goal

    #{blank_fallback(goal, "Clarise will help clarify this milestone through discussion.")}

    ## Why this matters

    ## Scope

    ## Non-goals

    ## Acceptance criteria

    ## Open questions

    ## Related artifacts

    - Discussion: #{linked_id(id, "discussion")}
    - Requirements: #{linked_id(id, "requirements")}
    - Plan: #{linked_id(id, "plan")}
    """
  end

  defp append_approval(body, approved_at, discussion_id, requirements_id, plan_id) do
    if Regex.match?(~r/^## Approval\b/m, body) do
      body
    else
      String.trim_trailing(body) <>
        """


        ## Approval

        Approved on: #{approved_at}
        This milestone is approved for implementation planning.
        Related artifacts:
        - Discussion: #{discussion_id}
        - Requirements: #{requirements_id}
        - Plan: #{plan_id}
        """
    end
  end

  defp put_heading_title(body, id, title) when is_binary(title) do
    number = suffix_number(id)
    Regex.replace(~r/^# Milestone .+$/m, body, "# Milestone #{number} - #{title}", global: false)
  end

  defp put_heading_title(body, _id, _title), do: body

  defp put_section(body, _heading, nil), do: body

  defp put_section(body, heading, value) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      body
    else
      pattern = ~r/(^## #{Regex.escape(heading)}\s*\n)(.*?)(?=^## |\z)/ms

      if Regex.match?(pattern, body) do
        Regex.replace(pattern, body, fn _all, header, _old -> header <> "\n" <> value <> "\n\n" end)
      else
        String.trim_trailing(body) <> "\n\n## #{heading}\n\n#{value}\n"
      end
    end
  end

  defp metadata_id(artifact, key, fallback) do
    case get_in(artifact, ["metadata", key]) do
      value when is_binary(value) and value != "" -> value
      _ -> fallback
    end
  end

  defp linked_id(milestone_id, suffix), do: "#{milestone_id}-#{suffix}"

  defp questions_payload do
    Enum.map(MilestoneDiscussion.questions(), fn {id, question} ->
      %{"id" => id, "question" => question}
    end)
  end

  defp string_attr(attrs, key) when is_map(attrs) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: nil, else: value

      _ ->
        nil
    end
  end

  defp string_attr(_attrs, _key), do: nil

  defp blank_fallback(value, fallback) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: fallback, else: value
  end

  defp blank_fallback(_value, fallback), do: fallback

  defp suffix_number("milestone-" <> number), do: number
  defp suffix_number(_id), do: "001"

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
