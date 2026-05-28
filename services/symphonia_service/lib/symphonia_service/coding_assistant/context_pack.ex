defmodule SymphoniaService.CodingAssistant.ContextPack do
  @moduledoc """
  Linked-only prompt context for Coding Assistant providers.

  The context pack is the single source used by runnable providers to render
  task prompts. It intentionally keeps raw provider output out of repository
  artifacts while still allowing private run metadata, such as a previous Codex
  thread id, to be reused for continuation runs.
  """

  alias SymphoniaService.{SpecWorkspace, Workspace}
  alias SymphoniaService.CodingAssistant.RunStore

  def build(repository, task, context, params \\ %{}) do
    assistant_input = Map.get(params, "assistant_input")

    %{
      "task" => %{
        "key" => task["key"],
        "title" => task["title"],
        "brief" => task_brief(task, assistant_input)
      },
      "workflow" => workflow(context, repository),
      "artifacts" => linked_artifacts(repository, task),
      "reviewExpectations" => review_expectations(task),
      "previousHandoff" => previous_handoff(task),
      "reviewNotes" => review_notes(task),
      "continuationFeedback" => continuation_feedback(assistant_input),
      "existingCodexThreadId" => existing_codex_thread_id(repository, task, params),
      "workspace" => workspace_facts(repository, context),
      "providerRules" => provider_rules()
    }
    |> reject_nil()
  end

  def render_prompt(repository, task, context, params \\ %{}, opts \\ []) do
    pack = build(repository, task, context, params)
    mode = Keyword.get(opts, :mode, :app_server)

    """
    You are the Coding Assistant working inside a Symphonía #{workspace_kind(mode)}.

    Task key: #{pack["task"]["key"]}
    Task title: #{pack["task"]["title"]}
    Repository: #{pack["workspace"]["repository"]}
    Base branch: #{pack["workspace"]["baseBranch"]}
    Head branch: #{pack["workspace"]["headBranch"]}
    Workspace path: #{pack["workspace"]["path"]}

    Task brief:
    #{pack["task"]["brief"]}

    #{continuation_section(pack)}
    #{previous_review_section(pack)}
    Review expectations:
    #{markdown_list(pack["reviewExpectations"], "- Review the changed files against the task acceptance criteria.")}

    Linked context:
    #{linked_context_section(pack["artifacts"])}

    WORKFLOW.md:
    #{pack["workflow"]}

    Rules:
    #{markdown_list(pack["providerRules"], "")}
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp workspace_kind(:codex), do: "repository workspace"
  defp workspace_kind(_mode), do: "persistent task workspace"

  defp workflow(context, repository) do
    repo_path = context_value(context, :repo_path) || repository["path"]

    case File.read(Path.join(repo_path, "WORKFLOW.md")) do
      {:ok, body} -> String.trim(body)
      {:error, _reason} -> Workspace.workflow(repository)["body"] || "No WORKFLOW.md found."
    end
  end

  defp linked_artifacts(repository, task) do
    []
    |> maybe_add_artifact(repository, "codebase_map", "codebase-map", "Codebase map")
    |> maybe_add_approved_milestone(repository, source_id(task, "source_milestone"))
    |> maybe_add_artifact(
      repository,
      "requirements",
      source_id(task, "source_requirements"),
      "Requirements"
    )
    |> maybe_add_artifact(repository, "plan", source_id(task, "source_plan"), "Plan")
    |> maybe_add_decisions(repository, source_list(task, "source_decisions"))
  end

  defp maybe_add_approved_milestone(artifacts, _repository, nil), do: artifacts

  defp maybe_add_approved_milestone(artifacts, repository, id) do
    case read_artifact(repository, "milestone", id) do
      %{"status" => "approved"} = artifact ->
        artifacts ++ [artifact_context("Approved milestone", artifact)]

      %{"metadata" => %{"status" => "approved"}} = artifact ->
        artifacts ++ [artifact_context("Approved milestone", artifact)]

      _ ->
        artifacts
    end
  end

  defp maybe_add_artifact(artifacts, _repository, _type, nil, _label), do: artifacts

  defp maybe_add_artifact(artifacts, repository, type, id, label) do
    case read_artifact(repository, type, id) do
      nil -> artifacts
      artifact -> artifacts ++ [artifact_context(label, artifact)]
    end
  end

  defp maybe_add_decisions(artifacts, repository, ids) do
    Enum.reduce(ids, artifacts, fn id, acc ->
      maybe_add_artifact(acc, repository, "decision", id, "Decision")
    end)
  end

  defp read_artifact(repository, type, id) do
    SpecWorkspace.read_artifact(repository, type, id)
  rescue
    _error -> nil
  end

  defp artifact_context(label, artifact) do
    %{
      "label" => label,
      "type" => artifact["type"],
      "id" => artifact["id"],
      "title" => artifact["title"],
      "status" => artifact["status"],
      "path" => artifact["path"],
      "body" => String.trim(artifact["body"] || "")
    }
    |> reject_nil()
  end

  defp review_expectations(task) do
    task
    |> Map.get("reviewExpectations", get_in(task, [:frontmatter, "review_expectations"]))
    |> List.wrap()
    |> Enum.reject(&blank?/1)
  end

  defp previous_handoff(task) do
    handoff = task["handoff"] || get_in(task, [:frontmatter, "handoff"])

    if is_map(handoff) and map_size(handoff) > 0 do
      summary = handoff["summary"]
      files = handoff["filesChanged"] || handoff["files_changed"] || []

      %{
        "summary" => summary,
        "filesChanged" => files,
        "headBranch" => handoff["headBranch"] || handoff["head_branch"],
        "curatedSummaryPath" => handoff["curatedSummaryPath"] || handoff["curated_summary_path"]
      }
      |> reject_nil()
    end
  end

  defp review_notes(task) do
    task
    |> Map.get("body", "")
    |> String.split(~r/\n## Review notes\b/, parts: 2)
    |> case do
      [_before, notes] ->
        notes
        |> String.split(~r/\n## Handoff history\b/, parts: 2)
        |> List.first()
        |> to_string()
        |> strip_original_feedback()
        |> String.trim()
        |> empty_to_nil()

      _ ->
        nil
    end
  end

  defp continuation_feedback(value) when is_binary(value) do
    value |> String.trim() |> empty_to_nil()
  end

  defp continuation_feedback(_value), do: nil

  defp existing_codex_thread_id(repository, task, params) do
    Map.get(params, "codex_thread_id") ||
      latest_private_codex_thread_id(repository, task) ||
      legacy_task_thread_id(task)
  end

  defp latest_private_codex_thread_id(repository, task) do
    RunStore.list()
    |> Enum.filter(fn run ->
      run["repository"] == repository["key"] and run["task"] == task["key"] and
        is_binary(run["codex_thread_id"]) and String.trim(run["codex_thread_id"]) != ""
    end)
    |> Enum.sort_by(&(&1["updated_at"] || &1["created_at"] || ""), :desc)
    |> List.first()
    |> case do
      nil -> nil
      run -> run["codex_thread_id"]
    end
  rescue
    _error -> nil
  end

  defp legacy_task_thread_id(task) do
    get_in(task, [:frontmatter, "run", "codex_thread_id"]) ||
      get_in(task, ["run", "codexThreadId"]) ||
      get_in(task, ["run", "codex_thread_id"])
  end

  defp workspace_facts(repository, context) do
    %{
      "repository" => repository["name"] || repository["key"],
      "baseBranch" => context_value(context, :base_branch),
      "headBranch" => context_value(context, :head_branch),
      "path" => context_value(context, :repo_path),
      "persistent" => context_value(context, :persistent) == true,
      "provider" => context_value(context, :workspace_provider)
    }
    |> reject_nil()
  end

  defp provider_rules do
    [
      "Make the code changes needed for the task in this workspace.",
      "Do not commit, push, or open a pull request; Symphonía will commit and push selected work-product files.",
      "Do not edit symphonia/tasks, symphonia/run-summaries, WORKFLOW.md, .symphonia, or registry files.",
      "Finish with a concise summary of what changed and any validation you performed."
    ]
  end

  defp linked_context_section([]), do: "No linked spec artifacts were found."

  defp linked_context_section(artifacts) do
    Enum.map_join(artifacts, "\n\n", fn artifact ->
      """
      #{artifact["label"]}: #{artifact["title"] || artifact["id"]} (#{artifact["path"]})
      Status: #{artifact["status"] || "unknown"}
      #{artifact["body"]}
      """
      |> String.trim()
    end)
  end

  defp continuation_section(%{"continuationFeedback" => feedback}) when is_binary(feedback) do
    "Continuation input:\n#{feedback}\n"
  end

  defp continuation_section(_pack), do: ""

  defp previous_review_section(pack) do
    [
      previous_handoff_section(pack["previousHandoff"]),
      review_notes_section(pack["reviewNotes"]),
      thread_section(pack["existingCodexThreadId"])
    ]
    |> Enum.reject(&blank?/1)
    |> case do
      [] -> ""
      values -> Enum.join(values, "\n\n") <> "\n"
    end
  end

  defp previous_handoff_section(nil), do: nil

  defp previous_handoff_section(handoff) do
    files =
      handoff["filesChanged"]
      |> List.wrap()
      |> Enum.reject(&blank?/1)
      |> markdown_list("No files recorded.")

    """
    Previous handoff:
    Summary: #{handoff["summary"] || "No summary recorded."}
    Files:
    #{files}
    """
    |> String.trim()
  end

  defp review_notes_section(nil), do: nil
  defp review_notes_section(notes), do: "Review notes:\n#{notes}"

  defp thread_section(nil), do: nil
  defp thread_section(thread_id), do: "Existing Codex thread ID: #{thread_id}"

  defp markdown_list([], fallback), do: fallback

  defp markdown_list(values, fallback) do
    values
    |> List.wrap()
    |> Enum.reject(&blank?/1)
    |> case do
      [] -> fallback
      items -> Enum.map_join(items, "\n", &"- #{&1}")
    end
  end

  defp task_brief(task, assistant_input) when is_binary(assistant_input) do
    task
    |> Map.get("body", "")
    |> strip_review_history()
    |> String.trim()
  end

  defp task_brief(task, _assistant_input), do: String.trim(task["body"] || "")

  defp strip_review_history(body) do
    body
    |> String.split(~r/\n## (Review notes|Handoff history)\b/, parts: 2)
    |> List.first()
    |> to_string()
  end

  defp strip_original_feedback(notes) do
    Regex.replace(
      ~r/\nOriginal feedback:\n.*?\n\nRequested changes:/s,
      notes,
      "\nRequested changes:"
    )
  end

  defp source_id(task, snake_key) do
    camel_key = snake_to_camel(snake_key)
    task[camel_key] || get_in(task, [:frontmatter, snake_key])
  end

  defp source_list(task, snake_key) do
    value = task[snake_to_camel(snake_key)] || get_in(task, [:frontmatter, snake_key])

    value
    |> List.wrap()
    |> Enum.reject(&blank?/1)
  end

  defp snake_to_camel("source_milestone"), do: "sourceMilestone"
  defp snake_to_camel("source_requirements"), do: "sourceRequirements"
  defp snake_to_camel("source_plan"), do: "sourcePlan"
  defp snake_to_camel("source_decisions"), do: "sourceDecisions"
  defp snake_to_camel(value), do: value

  defp context_value(context, key) when is_map(context) do
    Map.get(context, key) || Map.get(context, Atom.to_string(key))
  end

  defp context_value(_context, _key), do: nil

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  defp reject_nil(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")
end
