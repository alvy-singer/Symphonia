defmodule SymphoniaService.Clarise.RequirementsBuilder do
  @moduledoc """
  Deterministic requirements artifact builder for Clarise milestone setup.
  """

  def body(milestone, discussion) do
    title = milestone["title"] || "Untitled milestone"
    goal = section(milestone["body"], "Goal") || section(discussion["body"], "User intent")
    scope = section(milestone["body"], "Scope")
    non_goals = section(milestone["body"], "Non-goals")
    acceptance = section(milestone["body"], "Acceptance criteria")
    open_questions = section(discussion["body"], "Open questions")

    """
    # #{human_id(milestone["id"])} Requirements

    ## Goal

    #{fallback(goal, "Clarify the milestone goal before implementation planning.")}

    ## User stories

    - As a product user, I can understand what "#{title}" is meant to accomplish.
    - As a product user, I can review requirements before implementation planning starts.
    - As a product user, I can keep milestone context in editable Markdown.

    ## Functional requirements

    #{list_or_default(scope, ["Capture the milestone intent.", "Keep generated artifacts linked to the milestone.", "Make the artifacts readable and editable from the workspace."])}

    ## Non-functional requirements

    - Generated content must be deterministic.
    - Linked artifact ids must stay stable.
    - Existing task and Coding Assistant behavior must continue to work.

    ## Constraints

    - Markdown files remain the source of truth.
    - Raw local operational logs stay outside the repository.
    - Approved plans do not become executable tasks in this milestone.

    ## Non-goals

    #{list_or_default(non_goals, ["No plan-to-task compilation.", "No GitHub or Linear projection.", "No Coding Assistant run starts from an approved plan."])}

    ## Acceptance criteria

    #{list_or_default(acceptance, ["The milestone has a linked discussion.", "Requirements and plan artifacts are linked.", "Approval is blocked until required artifacts exist."])}

    ## Open questions

    #{fallback(open_questions, "No open questions recorded.")}
    """
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

  defp list_or_default(value, fallback_items) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" -> list_or_default(nil, fallback_items)
      String.contains?(value, "\n") -> value
      true -> "- #{value}"
    end
  end

  defp list_or_default(_value, fallback_items) do
    fallback_items
    |> Enum.map(&"- #{&1}")
    |> Enum.join("\n")
  end

  defp fallback(value, fallback) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: fallback, else: value
  end

  defp fallback(_value, fallback), do: fallback

  defp human_id("milestone-" <> number), do: "Milestone #{number}"
  defp human_id(id), do: id
end
