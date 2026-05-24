defmodule SymphoniaService.TaskStore do
  @moduledoc """
  Reads and writes task Markdown files under `symphonia/tasks`.
  """

  alias SymphoniaService.{Lifecycle, Markdown}

  def list_repositories(root \\ SymphoniaService.default_repositories_root()) do
    root
    |> File.ls!()
    |> Enum.filter(&File.dir?(Path.join(root, &1)))
    |> Enum.map(fn key ->
      %{
        "key" => key,
        "name" => repository_name(key),
        "path" => Path.join(root, key)
      }
    end)
  end

  def list_tasks(root, repo_key) do
    root
    |> task_glob(repo_key)
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&read_task_file(root, repo_key, &1))
  end

  def get_task(root, repo_key, task_key) do
    root
    |> list_tasks(repo_key)
    |> Enum.find(&(&1["key"] == task_key))
  end

  def patch_task(root, repo_key, task_key, patch) do
    task = get_task!(root, repo_key, task_key)

    frontmatter =
      task.frontmatter
      |> Map.merge(Map.get(patch, "frontmatter", %{}))
      |> maybe_put("title", Map.get(patch, "title"))
      |> Map.put("updated_at", now())

    body = Map.get(patch, "body", task.body)
    write_task(%{task | frontmatter: frontmatter, body: body})
  end

  def apply_event(root, repo_key, task_key, event, params \\ %{}) do
    task = get_task!(root, repo_key, task_key)

    task
    |> Lifecycle.apply_event(event, params)
    |> write_task()
  end

  defp task_glob(root, repo_key), do: Path.join([root, repo_key, "symphonia", "tasks", "*.md"])

  defp read_task_file(root, repo_key, path) do
    parsed = path |> File.read!() |> Markdown.parse()
    frontmatter = parsed.frontmatter

    %{
      "key" => frontmatter["key"],
      "title" => frontmatter["title"],
      "status" => frontmatter["status"],
      "priority" => frontmatter["priority"],
      "project" => frontmatter["project"],
      "assistant" => frontmatter["assistant"],
      "pausedReason" => frontmatter["paused_reason"],
      "pausedExplanation" => frontmatter["paused_explanation"],
      "githubIssue" => frontmatter["github_issue"],
      "githubIssueState" => frontmatter["github_issue_state"],
      "githubPr" => frontmatter["github_pr"],
      "githubPrState" => frontmatter["github_pr_state"],
      "githubSyncEnabled" => truthy?(frontmatter["github_sync_enabled"]),
      "reviewApproved" => truthy?(frontmatter["review_approved"]),
      "reviewSummary" => frontmatter["review_summary"],
      "filesChanged" => List.wrap(frontmatter["files_changed"]) |> Enum.reject(&is_nil/1),
      "nextReviewAction" => frontmatter["next_review_action"],
      "updatedAt" => frontmatter["updated_at"],
      "repo" => repo_key,
      "path" => Path.relative_to(path, Path.join(root, repo_key)),
      "body" => parsed.body,
      :repositories_root => root,
      :file_path => path,
      :frontmatter => frontmatter,
      :body => parsed.body
    }
  end

  defp get_task!(root, repo_key, task_key) do
    case get_task(root, repo_key, task_key) do
      nil -> raise ArgumentError, "task #{task_key} not found"
      task -> task
    end
  end

  defp write_task(task) do
    task.file_path
    |> File.write!(Markdown.serialize(task.frontmatter, task.body))

    read_task_file(task.repositories_root, task["repo"], task.file_path)
  end

  defp repository_name("SYM"), do: "agora-creations/symphonia"
  defp repository_name(key), do: key

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_), do: false

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
