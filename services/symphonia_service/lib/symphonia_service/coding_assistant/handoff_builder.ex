defmodule SymphoniaService.CodingAssistant.HandoffBuilder do
  @moduledoc """
  Builds and writes curated handoffs from Coding Assistant runs.
  """

  alias SymphoniaService.TaskStore

  def demo_file(task) do
    Path.join(["symphonia", "demo-output", "#{task["key"]}.md"])
  end

  def demo_body(task) do
    """
    # Demo Assistant Output
    This file was created by the Local Demo Assistant for task: #{task["title"]}.
    It proves the Coding Assistant run can create a branch, commit a change, push it, and produce a reviewable handoff.
    """
    |> String.trim_trailing()
    |> Kernel.<>("\n")
  end

  def build(task, branch) do
    file = demo_file(task)

    %{
      "summary" => "Created a demo output file for this task.",
      "files_changed" => [file],
      "next_review_action" => "Review the demo output and approve it to open a pull request.",
      "head_branch" => branch["head_branch"],
      "base_branch" => branch["base_branch"]
    }
  end

  def apply(repository, task_key, run, handoff) do
    TaskStore.patch_task(repository, task_key, %{
      "frontmatter" => %{
        "status" => "in_review",
        "assistant" => "local_demo",
        "paused_reason" => nil,
        "paused_explanation" => nil,
        "review_approved" => false,
        "review_state" => nil,
        "review_summary" => handoff["summary"],
        "files_changed" => handoff["files_changed"],
        "next_review_action" => handoff["next_review_action"],
        "next_step" => nil,
        "run" => %{
          "id" => run["id"],
          "state" => run["state"],
          "started_at" => run["started_at"],
          "completed_at" => run["completed_at"]
        },
        "handoff" => handoff
      }
    })
  end
end
