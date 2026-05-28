defmodule SymphoniaService.CodingAssistant.HandoffBuilder do
  @moduledoc """
  Builds and writes curated handoffs from Coding Assistant runs.
  """

  alias SymphoniaService.TaskStore
  alias SymphoniaService.CodingAssistant.{RunEvents, ValidationEvidence}

  def demo_file(task) do
    Path.join(["symphonia", "demo-output", "#{task["key"]}.md"])
  end

  def demo_body(task, assistant_input \\ nil) do
    base = """
    # Demo Assistant Output
    This file was created by the Local Demo Assistant for task: #{task["title"]}.
    It proves the Coding Assistant run can create a branch, commit a change, push it, and produce a reviewable handoff.
    """

    body =
      if is_binary(assistant_input) and String.trim(assistant_input) != "" do
        base <> "\n## Continuation input\n\n" <> String.trim(assistant_input) <> "\n"
      else
        base
      end

    body |> String.trim_trailing() |> Kernel.<>("\n")
  end

  def build(task, branch) do
    file = demo_file(task)

    %{
      "summary" => "Created a demo output file for this task.",
      "files_changed" => [file],
      "next_review_action" => "Review the demo output and approve it to open a pull request.",
      "head_branch" => branch["head_branch"],
      "base_branch" => branch["base_branch"],
      "validation_evidence" => ValidationEvidence.from_task(task)
    }
  end

  def build_from_changes(task, branch, files_changed, summary \\ nil) do
    files_changed = Enum.sort(files_changed)

    %{
      "summary" => clean_summary(summary, files_changed),
      "files_changed" => files_changed,
      "next_review_action" => "Review the changed files and approve them to open a pull request.",
      "head_branch" => branch["head_branch"],
      "base_branch" => branch["base_branch"],
      "validation_evidence" => ValidationEvidence.from_task(task)
    }
  end

  def apply(repository, task_key, run, handoff) do
    TaskStore.patch_task(repository, task_key, %{
      "frontmatter" => %{
        "status" => "in_review",
        "assistant" => run["provider"] || "coding_assistant",
        "paused_reason" => nil,
        "paused_explanation" => nil,
        "review_approved" => false,
        "review_state" => nil,
        "review_summary" => handoff["summary"],
        "files_changed" => handoff["files_changed"],
        "next_review_action" => handoff["next_review_action"],
        "next_step" => nil,
        "run" =>
          %{
            "id" => run["id"],
            "kind" => run["kind"],
            "state" => run["state"],
            "current_step" => run["current_step"],
            "message" => RunEvents.public_message(run),
            "display_step" => RunEvents.display_step(run),
            "display_message" => RunEvents.display_message(run),
            "eligibility_reason" => run["eligibility_reason"],
            "review_branch" => run["review_branch"],
            "curated_summary_path" => run["curated_summary_path"],
            "started_at" => run["started_at"],
            "completed_at" => run["completed_at"]
          }
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new(),
        "handoff" => handoff
      }
    })
  end

  defp clean_summary(summary, files_changed) when is_binary(summary) do
    summary
    |> String.trim()
    |> case do
      "" -> fallback_summary(files_changed)
      value -> value
    end
  end

  defp clean_summary(_summary, files_changed), do: fallback_summary(files_changed)

  defp fallback_summary(files_changed) do
    count = Enum.count(files_changed)
    suffix = if count == 1, do: "file", else: "files"
    "The Coding Assistant updated #{count} #{suffix}."
  end
end
