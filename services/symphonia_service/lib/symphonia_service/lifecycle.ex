defmodule SymphoniaService.Lifecycle do
  @moduledoc """
  Coding-run-driven task lifecycle transitions.
  """

  @valid_statuses ~w(todo in_progress in_review paused completed canceled)
  @valid_paused_reasons ~w(run_failed waiting_for_user blocked_by_setup waiting_for_sync needs_clarification)

  alias SymphoniaService.Clarise.FeedbackStructurer

  def valid_statuses, do: @valid_statuses
  def valid_paused_reasons, do: @valid_paused_reasons

  def apply_event(task, event, params \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    frontmatter = Map.get(task, :frontmatter) || Map.get(task, "frontmatter") || %{}
    body = Map.get(task, :body) || Map.get(task, "body") || ""

    {frontmatter, body} =
      case event do
        "start" ->
          frontmatter =
            frontmatter
            |> put_common(now)
            |> Map.put("status", "in_progress")
            |> Map.put("review_approved", false)
            |> Map.delete("paused_reason")
            |> Map.delete("paused_explanation")

          {frontmatter, body}

        "submit_review" ->
          summary =
            Map.get(params, "summary") ||
              "The Coding Assistant produced a reviewable handoff."

          files =
            Map.get(params, "files_changed") ||
              Map.get(params, "filesChanged") ||
              [frontmatter["key"] && "symphonia/tasks/#{frontmatter["key"]}.md"]
              |> Enum.reject(&is_nil/1)

          next_action =
            Map.get(params, "next_review_action") ||
              Map.get(params, "nextReviewAction") ||
              "Review the summary and files changed."

          frontmatter =
            frontmatter
            |> put_common(now)
            |> Map.merge(%{
              "status" => "in_review",
              "review_approved" => false,
              "review_summary" => summary,
              "files_changed" => files,
              "next_review_action" => next_action
            })

          {frontmatter, body}

        "fail_run" ->
          explanation =
            Map.get(params, "explanation") ||
              "The Coding Assistant could not produce a reviewable handoff."

          frontmatter =
            frontmatter
            |> put_common(now)
            |> Map.merge(%{
              "status" => "paused",
              "paused_reason" => "run_failed",
              "paused_explanation" => explanation
            })

          {frontmatter, body}

        "pause_run" ->
          explanation =
            Map.get(params, "explanation") ||
              "Run canceled. The task is paused. You can retry when ready."

          frontmatter =
            frontmatter
            |> put_common(now)
            |> Map.merge(%{
              "status" => "paused",
              "paused_reason" => "waiting_for_user",
              "paused_explanation" => explanation
            })

          {frontmatter, body}

        "approve" ->
          requires_pr = Map.get(params, "requires_pr", true)

          frontmatter =
            frontmatter
            |> put_common(now)
            |> Map.put("review_approved", true)
            |> Map.put("review_state", "approved")

          frontmatter =
            if requires_pr do
              frontmatter
              |> Map.put("status", "in_review")
              |> Map.put("next_step", "open_pull_request")
              |> Map.put("next_review_action", "Open pull request.")
            else
              frontmatter
              |> Map.put("status", "completed")
              |> Map.put("next_step", nil)
              |> Map.put("next_review_action", nil)
            end

          {frontmatter, body}

        "request_changes" ->
          feedback = Map.get(params, "feedback") || "Please make another pass."
          checklist = Map.get(params, "checklist") || structure_feedback(feedback)

          frontmatter =
            frontmatter
            |> put_common(now)
            |> Map.merge(%{
              "status" => "in_progress",
              "review_approved" => false,
              "review_state" => "changes_requested",
              "next_step" => nil,
              "next_review_action" => "Coding Assistant is continuing with requested changes."
            })

          {frontmatter, append_review_notes(body, feedback, checklist, now)}

        "open_pr" ->
          pr_url =
            Map.get(params, "github_pr") ||
              Map.get(params, "githubPr") ||
              "https://github.com/agora-creations/symphonia/pull/1"

          frontmatter =
            frontmatter
            |> put_common(now)
            |> Map.merge(%{
              "status" => "in_review",
              "github_pr" => pr_url,
              "github_pr_state" => "open",
              "next_step" => "refresh_pr_status",
              "next_review_action" => "Wait for pull request merge."
            })

          {frontmatter, body}

        "merge_pr" ->
          frontmatter =
            frontmatter
            |> put_common(now)
            |> Map.merge(%{
              "status" => "completed",
              "github_pr_state" => "merged",
              "next_step" => nil,
              "next_review_action" => nil
            })
            |> maybe_close_github_issue()

          {frontmatter,
           append_timeline(body, "Pull request merged. Linked GitHub issue updated.", now)}

        "cancel" ->
          {frontmatter |> put_common(now) |> Map.put("status", "canceled"), body}

        _ ->
          raise ArgumentError, "unknown lifecycle event: #{inspect(event)}"
      end

    %{task | frontmatter: frontmatter, body: body}
  end

  def structure_feedback(feedback) do
    FeedbackStructurer.structure(feedback)
  end

  defp put_common(frontmatter, now) do
    frontmatter
    |> Map.put("updated_at", now)
    |> Map.put_new("files_changed", [])
  end

  defp maybe_close_github_issue(%{"github_sync_enabled" => true} = frontmatter) do
    Map.put(frontmatter, "github_issue_state", "closed")
  end

  defp maybe_close_github_issue(%{"github_sync_enabled" => "true"} = frontmatter) do
    Map.put(frontmatter, "github_issue_state", "closed")
  end

  defp maybe_close_github_issue(frontmatter), do: frontmatter

  defp append_review_notes(body, feedback, checklist, now) do
    block = """

    ## Review notes

    ### Changes requested - #{now}

    Original feedback:
    #{feedback}

    Requested changes:
    #{Enum.map_join(checklist, "\n", &"- [ ] #{&1}")}
    """

    String.trim_trailing(body) <> "\n" <> block
  end

  defp append_timeline(body, note, now) do
    block = """

    ## Timeline

    - #{now}: #{note}
    """

    String.trim_trailing(body) <> "\n" <> block
  end
end
