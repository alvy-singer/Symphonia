defmodule SymphoniaService.Clarise.ReviewNotesBuilder do
  @moduledoc """
  Writes human review context into task Markdown.

  Frontmatter keeps the latest active handoff for UI. The body keeps the review
  and handoff trail so continuation runs do not erase human reasoning.
  """

  alias SymphoniaService.TaskStore

  def build(feedback, requested_changes, now \\ now()) do
    %{
      "id" => review_note_id(now),
      "created_at" => now,
      "original_feedback" => String.trim(feedback),
      "requested_changes" => requested_changes
    }
  end

  def apply(repository, task_key, review_note, continuation) do
    task = TaskStore.get_task(repository, task_key)
    frontmatter = Map.get(task, :frontmatter, %{})

    body =
      task["body"]
      |> append_handoff_history(frontmatter["handoff"], review_note["created_at"])
      |> append_review_note(review_note)

    TaskStore.patch_task(repository, task_key, %{
      "body" => body,
      "frontmatter" => %{
        "status" => "in_progress",
        "review_approved" => false,
        "review_state" => "changes_requested",
        "next_step" => nil,
        "next_review_action" => "Coding Assistant is continuing with requested changes.",
        "review_continuation" => continuation,
        "paused_reason" => nil,
        "paused_explanation" => nil
      }
    })
  end

  defp append_handoff_history(body, handoff, _now) when not is_map(handoff), do: body

  defp append_handoff_history(body, handoff, now) do
    summary = handoff["summary"]
    files = List.wrap(handoff["files_changed"]) |> Enum.reject(&is_nil/1)

    if blank?(summary) and files == [] do
      body
    else
      block = """

      ## Handoff history

      ### Handoff - #{now}

      Summary:
      #{summary || "No summary recorded."}

      Files changed:
      #{render_files(files)}
      #{render_optional("Next review action", handoff["next_review_action"])}
      #{render_optional("Head branch", handoff["head_branch"])}
      #{render_optional("Base branch", handoff["base_branch"])}
      """

      append_block(body, block)
    end
  end

  defp append_review_note(body, review_note) do
    block = """

    ## Review notes

    ### Changes requested - #{review_note["created_at"]}

    Original feedback:
    #{review_note["original_feedback"]}

    Requested changes:
    #{Enum.map_join(review_note["requested_changes"], "\n", &"- [ ] #{&1}")}
    """

    append_block(body, block)
  end

  defp append_block(body, block) do
    String.trim_trailing(body) <> "\n" <> String.trim_trailing(block) <> "\n"
  end

  defp render_files([]), do: "- No files recorded."
  defp render_files(files), do: Enum.map_join(files, "\n", &"- #{&1}")

  defp render_optional(_label, value) when value in [nil, ""], do: ""
  defp render_optional(label, value), do: "\n#{label}:\n#{value}\n"

  defp review_note_id(now) do
    suffix = now |> String.replace(~r/[^0-9A-Za-z]+/, "_") |> String.trim("_")
    unique = System.unique_integer([:positive])
    "review_note_#{suffix}_#{unique}"
  end

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
