defmodule SymphoniaService.CodingAssistant.CuratedSummary do
  @moduledoc """
  Writes review-safe run summaries into the private workspace.
  """

  alias SymphoniaService.CodingAssistant.ValidationEvidence
  alias SymphoniaService.PrivateWorkspace

  def write_private!(
        repository,
        task,
        run,
        files_changed,
        assistant_summary,
        validation_evidence \\ nil
      ) do
    validation_evidence = validation_evidence || ValidationEvidence.from_task(task)
    id = "#{slug(task["key"])}-codex-handoff"
    title = "#{task["key"]} Codex Run Summary"

    PrivateWorkspace.create_or_update_artifact(repository, "run_summary", id, %{
      "title" => title,
      "status" => "created",
      "source" => "coding_assistant",
      "task_key" => task["key"],
      "run_id" => run["id"],
      "body" => body(task, files_changed, assistant_summary, validation_evidence)
    })
  end

  defp body(task, files_changed, assistant_summary, validation_evidence) do
    summary =
      assistant_summary
      |> to_string()
      |> String.trim()
      |> case do
        "" -> "Codex App Server completed this task and produced reviewable changes."
        value -> value
      end

    """
    # #{task["key"]} Codex Run Summary

    ## Task

    #{task["title"]}

    ## Run

    - Worker: Codex
    - Completed at: #{DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()}

    ## Summary

    #{summary}

    ## Review Files

    #{markdown_list(files_changed)}

    ## Validation Evidence

    #{ValidationEvidence.markdown_list(validation_evidence)}

    ## Evidence Boundary

    Raw app-server events remain in the local Symphonía run store. This committed summary contains only curated review evidence.
    """
    |> String.trim_trailing()
    |> Kernel.<>("\n")
  end

  defp markdown_list(items) do
    items
    |> List.wrap()
    |> Enum.reject(&blank?/1)
    |> Enum.map_join("\n", &"- #{&1}")
    |> case do
      "" -> "- No files recorded."
      body -> body
    end
  end

  defp slug(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9._-]/, "-")
    |> String.trim("-")
    |> case do
      "" -> "run"
      slug -> slug
    end
  end

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")
end
