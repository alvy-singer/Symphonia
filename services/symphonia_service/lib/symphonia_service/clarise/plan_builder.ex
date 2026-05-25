defmodule SymphoniaService.Clarise.PlanBuilder do
  @moduledoc """
  Deterministic implementation-plan artifact builder for Clarise milestone setup.
  """

  def body(milestone, requirements) do
    title = milestone["title"] || "Untitled milestone"
    goal = section(requirements["body"], "Goal")
    functional = section(requirements["body"], "Functional requirements")
    non_goals = section(requirements["body"], "Non-goals")
    acceptance = section(requirements["body"], "Acceptance criteria")

    """
    # #{human_id(milestone["id"])} Plan

    ## Summary

    Implement "#{title}" by turning the approved requirements into focused product and service changes while keeping the existing task lifecycle intact.

    ## Implementation phases

    - Confirm the current workspace artifacts and linked milestone metadata.
    - Implement the backend service changes needed for the milestone.
    - Implement the workspace UI changes needed for the milestone.
    - Add regression tests and smoke checks.
    - Document validation and known limitations.

    ## Files and areas likely affected

    - Service modules under `services/symphonia_service/lib/symphonia_service`.
    - Repository API routes under `app/api/repositories`.
    - Workspace UI components and repository routes.
    - Milestone documentation under `docs`.

    ## Data model changes

    - Keep the data model as Markdown artifacts with metadata.
    - Preserve stable ids for linked milestone artifacts.
    - Do not change task status values.

    ## API changes

    - Add focused Clarise milestone-loop endpoints.
    - Keep existing spec workspace artifact endpoints working.
    - Keep existing task and Coding Assistant endpoints working.

    ## UI changes

    - Add a guided workspace dashboard for starting, discussing, planning, and approving a milestone.
    - Keep linked artifacts editable in the existing Markdown editor.
    - Avoid task-generation controls until a later milestone.

    ## Validation plan

    - Backend test coverage for each loop transition.
    - Type checking and production build for the web app.
    - Smoke checks for artifact creation, approval blocking, linked artifact editor access, and task board loading.

    ## Risks

    - Generated artifacts could overwrite useful edits if updates are not explicit.
    - Milestone statuses could be confused with task statuses.
    - Linked artifact metadata could drift if ids are not stable.

    ## Non-goals

    #{fallback(non_goals, "- No plan-to-task compiler.\n- No GitHub or Linear projection.\n- No Coding Assistant run starts from this plan.")}

    ## Ready for approval checklist

    - [ ] Discussion artifact exists.
    - [ ] Requirements artifact exists.
    - [ ] Plan artifact exists.
    - [ ] Acceptance criteria are reviewable.
    - [ ] Non-goals are clear.

    ## Source requirements

    #{fallback(functional || acceptance || goal, "Review the linked requirements artifact before approving this milestone.")}
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

  defp fallback(value, fallback) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: fallback, else: value
  end

  defp fallback(_value, fallback), do: fallback

  defp human_id("milestone-" <> number), do: "Milestone #{number}"
  defp human_id(id), do: id
end
