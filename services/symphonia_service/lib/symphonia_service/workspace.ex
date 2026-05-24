defmodule SymphoniaService.Workspace do
  @moduledoc """
  Detects and initializes the repository-local Symphonia workspace files.
  """

  @directories [
    "symphonia/projects",
    "symphonia/tasks",
    "symphonia/docs",
    "symphonia/reviews",
    "symphonia/decisions",
    "symphonia/run-summaries",
    "symphonia/templates"
  ]

  @templates %{
    "simple-pr" => %{
      "id" => "simple-pr",
      "label" => "Simple PR workflow",
      "description" => "Run, open a pull request, then complete when merged.",
      "body" =>
        "# WORKFLOW.md\n# Simple PR workflow\n\nCoding Assistants work from repo-backed task Markdown files.\n\non_task_started:\n  - assign: codex\n  - require_pr: true\n\non_run_complete:\n  - status: in_review\n  - notify_assignees: true\n\non_pr_merged:\n  - status: completed\n"
    },
    "review-first" => %{
      "id" => "review-first",
      "label" => "Review-first workflow",
      "description" => "Review the run summary in Symphonia before any PR.",
      "body" =>
        "# WORKFLOW.md\n# Review-first workflow\n\nHumans review the Coding Assistant handoff before a pull request opens.\n\non_task_started:\n  - assign: codex\n  - require_review: true\n\non_run_complete:\n  - status: in_review\n  - request_review_from: assignees\n\non_review_approved:\n  - open_pr: true\n\non_pr_merged:\n  - status: completed\n"
    },
    "persistent-retry" => %{
      "id" => "persistent-retry",
      "label" => "Persistent retry workflow",
      "description" => "Retry validation failures before review handoff.",
      "body" =>
        "# WORKFLOW.md\n# Persistent retry workflow\n\nCoding Assistants retry transient validation failures before handing work to review.\n\non_task_started:\n  - assign: codex\n  - require_pr: true\n\non_run_failed:\n  - retry:\n      max: 3\n      backoff: exponential\n\non_run_complete:\n  - validate:\n      - tests\n      - typecheck\n      - lint\n  - status: in_review\n\non_pr_merged:\n  - status: completed\n"
    }
  }

  def directories, do: @directories

  def templates do
    @templates
    |> Map.values()
    |> Enum.sort_by(& &1["label"])
  end

  def state(repository) do
    repo_path = repository["path"]

    missing_directories =
      @directories
      |> Enum.reject(&(repo_path |> Path.join(&1) |> File.dir?()))

    workflow_body =
      case File.read(workflow_path(repository)) do
        {:ok, body} -> body
        {:error, _reason} -> nil
      end

    %{
      "initialized" => missing_directories == [],
      "missingDirectories" => missing_directories,
      "workflow" => %{
        "exists" => is_binary(workflow_body),
        "valid" => is_binary(workflow_body) and String.trim(workflow_body) != ""
      }
    }
  end

  def initialize(repository) do
    for directory <- @directories do
      repository["path"]
      |> Path.join(directory)
      |> File.mkdir_p!()
    end

    state(repository)
  end

  def workflow(repository) do
    path = workflow_path(repository)

    case File.read(path) do
      {:ok, body} ->
        %{
          "exists" => true,
          "path" => "WORKFLOW.md",
          "body" => body,
          "templates" => templates()
        }

      {:error, :enoent} ->
        %{
          "exists" => false,
          "path" => "WORKFLOW.md",
          "body" => "",
          "templates" => templates()
        }

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read file", path: path
    end
  end

  def update_workflow(repository, body) when is_binary(body) do
    path = workflow_path(repository)

    unless File.exists?(path) do
      raise ArgumentError, "WORKFLOW.md does not exist. Create it from a template first."
    end

    File.write!(path, body)
    workflow(repository)
  end

  def create_workflow_from_template(repository, template_id) do
    path = workflow_path(repository)

    if File.exists?(path) do
      raise ArgumentError, "WORKFLOW.md already exists."
    end

    template =
      Map.get(@templates, template_id) || raise ArgumentError, "Unknown workflow template."

    File.write!(path, template["body"])
    workflow(repository)
  end

  defp workflow_path(repository), do: Path.join(repository["path"], "WORKFLOW.md")
end
