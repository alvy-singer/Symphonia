defmodule SymphoniaService.TaskStore do
  @moduledoc """
  Reads and writes task Markdown files under `symphonia/tasks`.
  """

  alias SymphoniaService.{Lifecycle, Markdown, RepositoryRegistry}

  def list_tasks(repository) when is_map(repository) do
    repository
    |> task_glob()
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&read_task_file(repository, &1))
  end

  def list_tasks(root, repo_key) do
    list_tasks(legacy_repository(root, repo_key))
  end

  def get_task(repository, task_key) when is_map(repository) do
    repository
    |> list_tasks()
    |> Enum.find(&(&1["key"] == task_key))
  end

  def get_task(root, repo_key, task_key) do
    root
    |> legacy_repository(repo_key)
    |> get_task(task_key)
  end

  def create_task(registry_path, repository, attrs) when is_map(repository) and is_map(attrs) do
    task_dir = task_directory(repository)

    unless File.dir?(task_dir) do
      raise ArgumentError,
            "Workspace folders are missing. Create workspace folders before adding tasks."
    end

    title = required_title!(attrs)
    body = body_from_attrs(attrs, title)
    {key, number, file_path} = next_task_key(repository)

    frontmatter =
      %{
        "key" => key,
        "title" => title,
        "status" => "todo",
        "priority" => priority_from_attrs(attrs),
        "project" => string_or_nil(Map.get(attrs, "project")),
        "assistant" => string_or_nil(Map.get(attrs, "assistant")),
        "files_changed" => [],
        "updated_at" => now()
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    File.write!(file_path, Markdown.serialize(frontmatter, body))

    RepositoryRegistry.update(registry_path, repository["key"], fn repo ->
      Map.put(repo, "last_task_number", max(number, repo["last_task_number"] || 0))
    end)

    read_task_file(repository, file_path)
  end

  def patch_task(repository, task_key, patch) when is_map(repository) do
    task = get_task!(repository, task_key)

    frontmatter =
      task.frontmatter
      |> Map.merge(Map.get(patch, "frontmatter", %{}))
      |> maybe_put("title", Map.get(patch, "title"))
      |> Map.put("updated_at", now())

    body = Map.get(patch, "body", task.body)
    write_task(%{task | frontmatter: frontmatter, body: body})
  end

  def patch_task(root, repo_key, task_key, patch) do
    root
    |> legacy_repository(repo_key)
    |> patch_task(task_key, patch)
  end

  def apply_event(repository, task_key, event) when is_map(repository) do
    apply_event(repository, task_key, event, %{})
  end

  def apply_event(repository, task_key, event, params) when is_map(repository) do
    task = get_task!(repository, task_key)

    task
    |> Lifecycle.apply_event(event, params)
    |> write_task()
  end

  def apply_event(root, repo_key, task_key, event) do
    apply_event(root, repo_key, task_key, event, %{})
  end

  def apply_event(root, repo_key, task_key, event, params) do
    root
    |> legacy_repository(repo_key)
    |> apply_event(task_key, event, params)
  end

  defp task_glob(repository), do: Path.join([repository["path"], "symphonia", "tasks", "*.md"])

  defp task_directory(repository), do: Path.join([repository["path"], "symphonia", "tasks"])

  defp read_task_file(repository, path) do
    parsed = path |> File.read!() |> Markdown.parse()
    frontmatter = parsed.frontmatter
    github = github_metadata(frontmatter)
    github_issue = github["issue"] || %{}
    github_pr = github["pull_request"] || %{}

    %{
      "key" => frontmatter["key"],
      "title" => frontmatter["title"],
      "status" => frontmatter["status"],
      "priority" => frontmatter["priority"],
      "project" => frontmatter["project"],
      "assistant" => frontmatter["assistant"],
      "pausedReason" => frontmatter["paused_reason"],
      "pausedExplanation" => frontmatter["paused_explanation"],
      "run" => public_run(frontmatter["run"]),
      "handoff" => public_handoff(frontmatter["handoff"]),
      "github" => public_github(github),
      "githubIssue" => github_issue["url"],
      "githubIssueState" => github_issue["state"],
      "githubPr" => github_pr["url"],
      "githubPrState" => github_pr["state"],
      "githubSyncEnabled" => truthy?(frontmatter["github_sync_enabled"]),
      "reviewApproved" => truthy?(frontmatter["review_approved"]),
      "reviewState" => frontmatter["review_state"],
      "reviewSummary" => frontmatter["review_summary"],
      "filesChanged" => List.wrap(frontmatter["files_changed"]) |> Enum.reject(&is_nil/1),
      "nextStep" => frontmatter["next_step"],
      "nextReviewAction" => frontmatter["next_review_action"],
      "updatedAt" => frontmatter["updated_at"],
      "repo" => repository["key"],
      "path" => Path.relative_to(path, repository["path"]),
      "body" => parsed.body,
      :repository => repository,
      :file_path => path,
      :frontmatter => frontmatter,
      :body => parsed.body
    }
  end

  defp get_task!(repository, task_key) do
    case get_task(repository, task_key) do
      nil -> raise ArgumentError, "task #{task_key} not found"
      task -> task
    end
  end

  defp write_task(task) do
    task.file_path
    |> File.write!(Markdown.serialize(task.frontmatter, task.body))

    read_task_file(task.repository, task.file_path)
  end

  defp next_task_key(repository) do
    prefix = repository["key"]

    existing_numbers =
      repository
      |> task_files()
      |> Enum.flat_map(&numbers_for_task_file(&1, prefix))

    last_number = repository["last_task_number"] || 0
    starting_number = Enum.max([last_number | existing_numbers]) + 1

    find_free_task_key(repository, prefix, starting_number)
  end

  defp find_free_task_key(repository, prefix, number) do
    key = "#{prefix}-#{number}"
    file_path = Path.join(task_directory(repository), "#{key}.md")

    if File.exists?(file_path) do
      find_free_task_key(repository, prefix, number + 1)
    else
      {key, number, file_path}
    end
  end

  defp task_files(repository), do: repository |> task_glob() |> Path.wildcard()

  defp numbers_for_task_file(path, prefix) do
    filename_number =
      path
      |> Path.basename(".md")
      |> task_number(prefix)

    frontmatter_number =
      path
      |> File.read!()
      |> Markdown.parse()
      |> Map.get(:frontmatter)
      |> Map.get("key")
      |> task_number(prefix)

    [filename_number, frontmatter_number]
    |> Enum.reject(&is_nil/1)
  end

  defp task_number(nil, _prefix), do: nil

  defp task_number(value, prefix) when is_binary(value) do
    case Regex.run(~r/^#{Regex.escape(prefix)}-(\d+)$/, value) do
      [_all, number] -> String.to_integer(number)
      _ -> nil
    end
  end

  defp required_title!(attrs) do
    case Map.get(attrs, "title") do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: raise(ArgumentError, "Task title is required."), else: value

      _ ->
        raise ArgumentError, "Task title is required."
    end
  end

  defp body_from_attrs(attrs, title) do
    case Map.get(attrs, "body") || Map.get(attrs, "description") do
      value when is_binary(value) and value != "" ->
        body = String.trim_leading(value)
        if String.starts_with?(body, "#"), do: body, else: "# #{title}\n\n#{body}"

      _ ->
        "# #{title}\n\n"
    end
  end

  defp priority_from_attrs(attrs) do
    case Map.get(attrs, "priority") do
      value when value in ["urgent", "high", "medium", "low", "no-priority"] -> value
      _ -> "no-priority"
    end
  end

  defp string_or_nil(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp string_or_nil(_value), do: nil

  defp legacy_repository(root, repo_key) do
    %{
      "key" => repo_key,
      "name" => repo_key,
      "path" => Path.join(root, repo_key),
      "last_task_number" => 0
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp github_metadata(frontmatter) do
    github =
      case frontmatter["github"] do
        value when is_map(value) -> value
        _ -> %{}
      end

    github
    |> put_legacy_issue(frontmatter)
    |> put_legacy_pr(frontmatter)
  end

  defp put_legacy_issue(github, frontmatter) do
    cond do
      is_map(github["issue"]) ->
        github

      is_binary(frontmatter["github_issue"]) and frontmatter["github_issue"] != "" ->
        Map.put(github, "issue", %{
          "url" => frontmatter["github_issue"],
          "state" => frontmatter["github_issue_state"],
          "number" => number_from_url(frontmatter["github_issue"], "issues")
        })

      true ->
        github
    end
  end

  defp put_legacy_pr(github, frontmatter) do
    cond do
      is_map(github["pull_request"]) ->
        github

      is_binary(frontmatter["github_pr"]) and frontmatter["github_pr"] != "" ->
        Map.put(github, "pull_request", %{
          "url" => frontmatter["github_pr"],
          "state" => frontmatter["github_pr_state"],
          "merged" => frontmatter["github_pr_state"] == "merged",
          "number" => number_from_url(frontmatter["github_pr"], "pull")
        })

      true ->
        github
    end
  end

  defp public_github(github) when github == %{}, do: nil
  defp public_github(github), do: github

  defp public_run(run) when is_map(run) do
    %{
      "id" => run["id"],
      "state" => run["state"],
      "startedAt" => run["started_at"],
      "completedAt" => run["completed_at"]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp public_run(_run), do: nil

  defp public_handoff(handoff) when is_map(handoff) do
    %{
      "summary" => handoff["summary"],
      "filesChanged" => List.wrap(handoff["files_changed"]) |> Enum.reject(&is_nil/1),
      "nextReviewAction" => handoff["next_review_action"],
      "headBranch" => handoff["head_branch"],
      "baseBranch" => handoff["base_branch"]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp public_handoff(_handoff), do: nil

  defp number_from_url(nil, _segment), do: nil

  defp number_from_url(url, segment) do
    case Regex.run(~r/#{segment}\/(\d+)/, url) do
      [_all, number] -> String.to_integer(number)
      _ -> nil
    end
  end

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_), do: false

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
