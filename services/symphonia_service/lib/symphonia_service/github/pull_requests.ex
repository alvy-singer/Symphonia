defmodule SymphoniaService.GitHub.PullRequests do
  @moduledoc """
  Opens and refreshes GitHub pull requests for approved task handoffs.
  """

  alias SymphoniaService.{TaskStore}
  alias SymphoniaService.GitHub.{Auth, Client, Issues, RepositoryLink}

  @push_branch_error "Push a task branch before opening a pull request."

  def push_branch_error, do: @push_branch_error

  def open_from_task(repository, task_key) do
    task = get_task!(repository, task_key)
    frontmatter = task.frontmatter
    ensure_approved!(task, frontmatter)
    github_repo = github_repo!(repository, frontmatter)
    head_branch = head_branch!(frontmatter)
    base_branch = base_branch(frontmatter, github_repo)
    token = Auth.user_token!()

    ensure_branch_exists!(token, github_repo, head_branch)

    payload = %{
      "title" => pr_title(task),
      "body" => pr_body(task),
      "head" => head_branch,
      "base" => base_branch
    }

    case client().create_pull_request(token, github_repo["owner"], github_repo["name"], payload) do
      {:ok, pr} ->
        github =
          put_pull_request(
            github_metadata(frontmatter),
            github_repo,
            pr,
            head_branch,
            base_branch
          )

        TaskStore.patch_task(repository, task_key, %{
          "frontmatter" => %{
            "status" => "in_review",
            "next_step" => "refresh_pr_status",
            "next_review_action" => "Review or merge the pull request to continue the workflow.",
            "github" => github
          },
          "body" => append_timeline(task.body, "Pull request opened.", now())
        })

      {:error, payload} ->
        raise ArgumentError, Map.get(payload, "message", "Could not open pull request.")
    end
  end

  def refresh(repository, task_key) do
    task = get_task!(repository, task_key)
    frontmatter = task.frontmatter
    github = github_metadata(frontmatter)
    github_repo = github_repo!(repository, frontmatter)
    pr = Map.get(github, "pull_request") || %{}
    number = pr["number"] || raise ArgumentError, "This task does not have an open pull request."
    token = Auth.user_token!()

    case client().get_pull_request(token, github_repo["owner"], github_repo["name"], number) do
      {:ok, fresh_pr} ->
        merged? = fresh_pr["merged"] == true
        pr_state = if merged?, do: "merged", else: fresh_pr["state"] || pr["state"] || "open"

        github =
          put_in(github, ["pull_request"], %{
            "owner" => github_repo["owner"],
            "repo" => github_repo["name"],
            "number" => fresh_pr["number"] || number,
            "url" => fresh_pr["html_url"] || pr["url"],
            "state" => pr_state,
            "merged" => merged?,
            "head_branch" => get_in(fresh_pr, ["head", "ref"]) || pr["head_branch"],
            "base_branch" => get_in(fresh_pr, ["base", "ref"]) || pr["base_branch"]
          })

        if merged? do
          complete_after_merge(repository, task, github_repo, github, token)
        else
          TaskStore.patch_task(repository, task_key, %{
            "frontmatter" => %{
              "status" => "in_review",
              "github" => github,
              "next_step" => "refresh_pr_status",
              "next_review_action" => "Review or merge the pull request to continue the workflow."
            }
          })
        end

      {:error, payload} ->
        raise ArgumentError, Map.get(payload, "message", "Could not refresh pull request.")
    end
  end

  defp complete_after_merge(repository, task, github_repo, github, token) do
    {github, issue_note} = close_linked_issue!(token, github_repo, github)

    body =
      task.body
      |> append_timeline("Pull request merged.", now())
      |> append_timeline("Task completed.", now())
      |> maybe_append_issue_note(issue_note)

    TaskStore.patch_task(repository, task["key"], %{
      "frontmatter" => %{
        "status" => "completed",
        "next_step" => nil,
        "next_review_action" => nil,
        "github" => github
      },
      "body" => body
    })
  end

  defp close_linked_issue!(token, github_repo, github) do
    issue = github["issue"]

    case Issues.close_linked_issue(token, github_repo, issue) do
      {:ok, nil} ->
        {github, nil}

      {:ok, updated_issue} ->
        issue =
          (issue || %{})
          |> Map.put("state", updated_issue["state"] || "closed")
          |> Map.put("url", updated_issue["html_url"] || issue["url"])

        {Map.put(github, "issue", issue), "Linked GitHub issue closed automatically."}

      {:error, payload} ->
        raise ArgumentError, Map.get(payload, "message", "Could not update linked GitHub issue.")
    end
  end

  defp ensure_branch_exists!(token, github_repo, head_branch) do
    case client().get_branch(token, github_repo["owner"], github_repo["name"], head_branch) do
      {:ok, _branch} ->
        :ok

      {:error, %{"status" => 404}} ->
        raise ArgumentError, @push_branch_error

      {:error, payload} ->
        raise ArgumentError, Map.get(payload, "message", @push_branch_error)
    end
  end

  defp ensure_approved!(task, frontmatter) do
    unless task["reviewApproved"] or frontmatter["review_state"] == "approved" do
      raise ArgumentError, "Approve the handoff before opening a pull request."
    end
  end

  defp github_repo!(repository, frontmatter) do
    repo_from_task = get_in(github_metadata(frontmatter), ["repo"]) || %{}
    link = RepositoryLink.link(repository) || %{}

    owner = repo_from_task["owner"] || link["owner"]
    name = repo_from_task["name"] || link["name"]

    if blank?(owner) or blank?(name) do
      raise ArgumentError, "Link this local repository to GitHub before opening a pull request."
    end

    %{
      "owner" => owner,
      "name" => name,
      "url" => repo_from_task["url"] || link["url"],
      "default_branch" =>
        repo_from_task["default_branch"] || link["defaultBranch"] || link["default_branch"]
    }
  end

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
    if github["issue"] || blank?(frontmatter["github_issue"]) do
      github
    else
      Map.put(github, "issue", %{
        "url" => frontmatter["github_issue"],
        "state" => frontmatter["github_issue_state"],
        "number" => number_from_url(frontmatter["github_issue"], "issues")
      })
    end
  end

  defp put_legacy_pr(github, frontmatter) do
    if github["pull_request"] || blank?(frontmatter["github_pr"]) do
      github
    else
      Map.put(github, "pull_request", %{
        "url" => frontmatter["github_pr"],
        "state" => frontmatter["github_pr_state"],
        "merged" => frontmatter["github_pr_state"] == "merged",
        "number" => number_from_url(frontmatter["github_pr"], "pull")
      })
    end
  end

  defp put_pull_request(github, github_repo, pr, head_branch, base_branch) do
    github
    |> Map.put("repo", %{
      "owner" => github_repo["owner"],
      "name" => github_repo["name"]
    })
    |> Map.put("pull_request", %{
      "owner" => github_repo["owner"],
      "repo" => github_repo["name"],
      "number" => pr["number"],
      "url" => pr["html_url"],
      "state" => pr["state"] || "open",
      "merged" => false,
      "head_branch" => get_in(pr, ["head", "ref"]) || head_branch,
      "base_branch" => get_in(pr, ["base", "ref"]) || base_branch
    })
  end

  defp head_branch!(frontmatter) do
    github_branch = get_in(github_metadata(frontmatter), ["pull_request", "head_branch"])
    handoff_branch = get_in(frontmatter, ["handoff", "head_branch"])

    branch =
      github_branch || handoff_branch || frontmatter["handoff_head_branch"] ||
        frontmatter["github_head_branch"]

    if blank?(branch), do: raise(ArgumentError, @push_branch_error), else: branch
  end

  defp base_branch(frontmatter, github_repo) do
    get_in(github_metadata(frontmatter), ["pull_request", "base_branch"]) ||
      get_in(frontmatter, ["handoff", "base_branch"]) ||
      github_repo["default_branch"] ||
      "main"
  end

  defp pr_title(task), do: "#{task["key"]}: #{task["title"]}"

  defp pr_body(task) do
    """
    #{task["reviewSummary"] || "Approved Symphonia handoff."}

    Task: #{task["key"]} - #{task["title"]}

    Files changed:
    #{files_changed(task)}
    """
    |> String.trim()
  end

  defp files_changed(task) do
    case task["filesChanged"] do
      values when is_list(values) and values != [] -> Enum.map_join(values, "\n", &"- #{&1}")
      _ -> "- Not recorded"
    end
  end

  defp get_task!(repository, task_key) do
    case TaskStore.get_task(repository, task_key) do
      nil -> raise ArgumentError, "task #{task_key} not found"
      task -> task
    end
  end

  defp number_from_url(nil, _segment), do: nil

  defp number_from_url(url, segment) do
    case Regex.run(~r/#{segment}\/(\d+)/, url) do
      [_all, number] -> String.to_integer(number)
      _ -> nil
    end
  end

  defp append_timeline(body, note, timestamp) do
    block = """

    ## Timeline

    - #{timestamp}: #{note}
    """

    String.trim_trailing(body || "") <> "\n" <> block
  end

  defp maybe_append_issue_note(body, nil), do: body
  defp maybe_append_issue_note(body, note), do: append_timeline(body, note, now())

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp client do
    Application.get_env(:symphonia_service, :github_client, Client)
  end
end
