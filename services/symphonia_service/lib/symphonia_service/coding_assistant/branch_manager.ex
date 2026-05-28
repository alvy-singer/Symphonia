defmodule SymphoniaService.CodingAssistant.BranchManager do
  @moduledoc """
  Creates and pushes the Coding Assistant work-product branch.
  """

  alias SymphoniaService.GitHub.{Auth, RepositoryLink}

  @git_author ["-c", "user.name=Symphonia", "-c", "user.email=symphonia@example.invalid"]

  def create_and_push_demo_change(repository, task, file_path, file_body) do
    github = github_repo!(repository)
    token = Auth.token_for_repository(github["owner"], github["name"])
    repo_path = repository["path"]
    base_branch = github["default_branch"] || "main"
    head_branch = task_branch(task)
    previous_branch = current_branch(repo_path)

    remote_url =
      github["clone_url"] || "https://github.com/#{github["owner"]}/#{github["name"]}.git"

    try do
      with_auth(token, fn auth ->
        fetch_base!(repo_path, remote_url, base_branch, auth)
        checkout_branch!(repo_path, head_branch, base_branch)
        write_work_product!(repo_path, file_path, file_body)
        commit_work_product!(repo_path, task, file_path)
        push_branch!(repo_path, remote_url, head_branch, auth)
      end)
    after
      restore_branch(repo_path, previous_branch)
    end

    %{"head_branch" => head_branch, "base_branch" => base_branch, "files_changed" => [file_path]}
  end

  def with_task_branch_worktree(repository, task, fun) when is_function(fun, 1) do
    ensure_repo_ready_for_task_branch!(repository, task)

    github = github_repo!(repository)
    token = Auth.token_for_repository(github["owner"], github["name"])
    repo_path = repository["path"]
    base_branch = github["default_branch"] || "main"
    head_branch = task_branch(task)
    worktree_path = temp_worktree_path(task)

    remote_url =
      github["clone_url"] || "https://github.com/#{github["owner"]}/#{github["name"]}.git"

    try do
      with_auth(token, fn auth ->
        fetch_base!(repo_path, remote_url, base_branch, auth)
        add_worktree!(repo_path, worktree_path, head_branch, base_branch)

        context = %{
          auth: auth,
          base_branch: base_branch,
          head_branch: head_branch,
          remote_url: remote_url,
          repo_path: worktree_path,
          source_repo_path: repo_path
        }

        case fun.(context) do
          {:ok, result} ->
            {:ok,
             Map.merge(result, %{
               "head_branch" => head_branch,
               "base_branch" => base_branch,
               "worktree_path" => worktree_path
             })}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    after
      remove_worktree(repo_path, worktree_path)
    end
  end

  def with_persistent_task_branch_worktree(repository, task, fun) when is_function(fun, 1) do
    context = prepare_persistent_task_branch_worktree!(repository, task)

    try do
      case fun.(context) do
        {:ok, result} ->
          {:ok,
           Map.merge(result, %{
             "head_branch" => context.head_branch,
             "base_branch" => context.base_branch,
             "worktree_path" => context.repo_path
           })}

        {:error, reason} ->
          {:error, reason}
      end
    after
      release_persistent_task_branch_worktree(context)
    end
  end

  def prepare_persistent_task_branch_worktree!(repository, task) do
    ensure_repo_ready_for_task_branch!(repository, task)

    github = github_repo!(repository)
    token = Auth.token_for_repository(github["owner"], github["name"])
    repo_path = repository["path"]
    base_branch = github["default_branch"] || "main"
    head_branch = task_branch(task)
    worktree_path = SymphoniaService.Harness.TaskWorkspace.path(repository, task)

    remote_url =
      github["clone_url"] || "https://github.com/#{github["owner"]}/#{github["name"]}.git"

    auth = auth_context(token)

    try do
      fetch_base!(repo_path, remote_url, base_branch, auth)
      fetch_branch(repo_path, remote_url, head_branch, auth)
      prepare_persistent_worktree!(repo_path, worktree_path, head_branch, base_branch)

      %{
        auth: auth,
        base_branch: base_branch,
        head_branch: head_branch,
        remote_url: remote_url,
        repo_path: worktree_path,
        source_repo_path: repo_path,
        persistent: true,
        workspace_provider: "local_git_worktree"
      }
    rescue
      error ->
        release_auth(auth)
        reraise error, __STACKTRACE__
    end
  end

  def release_persistent_task_branch_worktree(context) when is_map(context) do
    release_auth(context[:auth] || context["auth"])
    :ok
  end

  def release_persistent_task_branch_worktree(_context), do: :ok

  def ensure_repo_ready_for_task_branch!(repository, task) do
    repo_path = repository["path"]

    cond do
      blank?(repo_path) or not File.dir?(repo_path) ->
        raise ArgumentError,
              "The Coding Assistant can't start because the repository path is missing."

      not git_repo?(repo_path) ->
        raise ArgumentError,
              "The Coding Assistant can't start because this folder is not a Git repository."

      true ->
        :ok
    end

    github_repo!(repository)
    ensure_task_branch_name!(task_branch(task))
    ensure_clean_tracked_worktree!(repo_path)
    :ok
  end

  def commit_files!(context, task, files) when is_list(files) do
    files = Enum.reject(files, &blank?/1)

    if files == [] do
      raise ArgumentError, "The Coding Assistant did not produce any files that can be reviewed."
    end

    git!(context.repo_path, ["add", "--" | files])

    git!(
      context.repo_path,
      @git_author ++ ["commit", "-m", "#{task["key"]} coding assistant changes", "--" | files]
    )
  end

  def push_task_branch!(context) do
    push_branch!(context.repo_path, context.remote_url, context.head_branch, context.auth)
  end

  def review_branch_exists?(repository, task) do
    github = github_repo!(repository)
    token = Auth.token_for_repository(github["owner"], github["name"])
    repo_path = repository["path"]

    remote_url =
      github["clone_url"] || "https://github.com/#{github["owner"]}/#{github["name"]}.git"

    with_auth(token, fn auth ->
      not is_nil(remote_head(repo_path, remote_url, task_branch(task), auth))
    end)
  end

  def revert_paths!(repo_path, paths) when is_list(paths) do
    paths = Enum.reject(paths, &blank?/1)

    if paths != [] do
      git(repo_path, ["checkout", "--" | paths])
      git(repo_path, ["clean", "-fd", "--" | paths])
    end

    :ok
  end

  def task_branch(task), do: "symphonia/task/#{slug(task["key"])}"

  def github_repo!(repository) do
    link = RepositoryLink.link(repository) || %{}

    owner = link["owner"]
    name = link["name"]

    if blank?(owner) or blank?(name) do
      raise ArgumentError,
            "Link this local repository to GitHub before assigning a Coding Assistant."
    end

    %{
      "owner" => owner,
      "name" => name,
      "clone_url" => link["cloneUrl"] || link["clone_url"],
      "default_branch" => link["defaultBranch"] || link["default_branch"] || "main"
    }
  end

  defp git_repo?(repo_path) do
    case git(repo_path, ["rev-parse", "--is-inside-work-tree"]) do
      {:ok, "true"} -> true
      _ -> false
    end
  end

  defp ensure_clean_tracked_worktree!(repo_path) do
    case git(repo_path, ["status", "--porcelain", "--untracked-files=no"]) do
      {:ok, ""} ->
        :ok

      {:ok, status} ->
        dirty_work_product_files =
          status
          |> changed_paths()
          |> Enum.reject(&metadata_path?/1)

        if dirty_work_product_files == [] do
          :ok
        else
          raise ArgumentError,
                "The Coding Assistant can't start because this repository has uncommitted changes."
        end

      {:error, output} ->
        raise ArgumentError, clean_git_error(output)
    end
  end

  defp ensure_task_branch_name!("symphonia/task/" <> rest) when rest != "", do: :ok

  defp ensure_task_branch_name!(_branch) do
    raise ArgumentError,
          "The Coding Assistant can't start because the task branch name is invalid."
  end

  defp fetch_base!(repo_path, remote_url, base_branch, askpass) do
    ref = "refs/heads/#{base_branch}:refs/remotes/symphonia/#{base_branch}"
    git!(repo_path, ["fetch", "--depth=1", remote_url, ref], askpass)
  end

  defp fetch_branch(repo_path, remote_url, branch, askpass) do
    ref = "refs/heads/#{branch}:refs/remotes/symphonia/#{branch}"
    git(repo_path, ["fetch", "--depth=1", remote_url, ref], askpass)
    :ok
  end

  defp add_worktree!(repo_path, worktree_path, head_branch, base_branch) do
    File.rm_rf(worktree_path)

    git!(
      repo_path,
      [
        "worktree",
        "add",
        "--force",
        "-B",
        head_branch,
        worktree_path,
        "refs/remotes/symphonia/#{base_branch}"
      ]
    )
  end

  defp prepare_persistent_worktree!(repo_path, worktree_path, head_branch, base_branch) do
    worktree_path |> Path.dirname() |> File.mkdir_p!()
    start_ref = persistent_start_ref(repo_path, head_branch, base_branch)

    if git_repo?(worktree_path) do
      git!(worktree_path, ["checkout", "-B", head_branch, start_ref])
      git!(worktree_path, ["reset", "--hard", start_ref])
      git!(worktree_path, ["clean", "-fd"])
    else
      File.rm_rf(worktree_path)

      git!(
        repo_path,
        [
          "worktree",
          "add",
          "--force",
          "-B",
          head_branch,
          worktree_path,
          start_ref
        ]
      )
    end
  end

  defp persistent_start_ref(repo_path, head_branch, base_branch) do
    head_ref = "refs/remotes/symphonia/#{head_branch}"

    case git(repo_path, ["rev-parse", "--verify", head_ref]) do
      {:ok, _sha} -> head_ref
      _ -> "refs/remotes/symphonia/#{base_branch}"
    end
  end

  defp checkout_branch!(repo_path, head_branch, base_branch) do
    git!(repo_path, ["checkout", "-B", head_branch, "refs/remotes/symphonia/#{base_branch}"])
  end

  defp write_work_product!(repo_path, file_path, file_body) do
    full_path = Path.join(repo_path, file_path)
    full_path |> Path.dirname() |> File.mkdir_p!()
    File.write!(full_path, file_body)
  end

  defp commit_work_product!(repo_path, task, file_path) do
    git!(repo_path, ["add", "--", file_path])

    git!(
      repo_path,
      @git_author ++ ["commit", "-m", "#{task["key"]} demo assistant output", "--", file_path]
    )
  end

  defp push_branch!(repo_path, remote_url, head_branch, askpass) do
    lease =
      case remote_head(repo_path, remote_url, head_branch, askpass) do
        nil -> "--force-with-lease=refs/heads/#{head_branch}:"
        sha -> "--force-with-lease=refs/heads/#{head_branch}:#{sha}"
      end

    git!(
      repo_path,
      ["push", lease, remote_url, "HEAD:refs/heads/#{head_branch}"],
      askpass
    )
  end

  defp remove_worktree(repo_path, worktree_path) do
    git(repo_path, ["worktree", "remove", "--force", worktree_path])
    File.rm_rf(worktree_path)
    :ok
  end

  defp changed_paths(status) do
    status
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      path = String.slice(line, 3..-1//1) || ""

      case String.split(path, " -> ", parts: 2) do
        [_from, to] -> String.trim(to)
        [single] -> String.trim(single)
      end
    end)
  end

  defp metadata_path?(".symphonia/" <> _rest), do: true
  defp metadata_path?("symphonia/tasks/" <> _rest), do: true
  defp metadata_path?("symphonia/run-summaries/" <> _rest), do: true
  defp metadata_path?("WORKFLOW.md"), do: true
  defp metadata_path?("registry.json"), do: true
  defp metadata_path?("repositories.json"), do: true
  defp metadata_path?("symphonia/registry.json"), do: true
  defp metadata_path?("symphonia/repositories.json"), do: true
  defp metadata_path?(_path), do: false

  defp remote_head(repo_path, remote_url, head_branch, askpass) do
    case git(repo_path, ["ls-remote", remote_url, "refs/heads/#{head_branch}"], askpass) do
      {:ok, ""} ->
        nil

      {:ok, output} ->
        output
        |> String.split()
        |> List.first()

      {:error, _output} ->
        nil
    end
  end

  defp current_branch(repo_path) do
    case git(repo_path, ["rev-parse", "--abbrev-ref", "HEAD"]) do
      {:ok, "HEAD"} -> nil
      {:ok, branch} -> branch
      _ -> nil
    end
  end

  defp restore_branch(_repo_path, nil), do: :ok

  defp restore_branch(repo_path, previous_branch) do
    git(repo_path, ["checkout", previous_branch])
    :ok
  end

  defp with_auth(token, fun) do
    auth = auth_context(token)

    try do
      fun.(auth)
    after
      release_auth(auth)
    end
  end

  defp auth_context(token) do
    askpass = askpass_path()

    File.write!(askpass, """
    #!/bin/sh
    case "$1" in
      *Username*) echo x-access-token ;;
      *) printf '%s\\n' "$SYMPHONIA_GIT_TOKEN" ;;
    esac
    """)

    File.chmod(askpass, 0o700)

    %{askpass: askpass, token: token}
  end

  defp release_auth(%{askpass: askpass}) do
    File.rm(askpass)
    :ok
  rescue
    _ -> :ok
  end

  defp release_auth(_auth), do: :ok

  defp askpass_path do
    Path.join(System.tmp_dir!(), "symphonia-git-askpass-#{System.unique_integer([:positive])}.sh")
  end

  defp temp_worktree_path(task) do
    Path.join(
      System.tmp_dir!(),
      "symphonia-codex-worktree-#{slug(task["key"])}-#{System.unique_integer([:positive])}"
    )
  end

  defp git!(repo_path, args, askpass \\ nil) do
    case git(repo_path, args, askpass) do
      {:ok, output} ->
        output

      {:error, output} ->
        raise ArgumentError, clean_git_error(output)
    end
  end

  defp git(repo_path, args, auth \\ nil) do
    opts = [stderr_to_stdout: true]
    opts = if auth, do: Keyword.put(opts, :env, git_env(auth)), else: opts

    case System.cmd("git", ["-C", repo_path | args], opts) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, _status} -> {:error, output}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp git_env(%{askpass: askpass, token: token}) do
    [
      {"GIT_ASKPASS", askpass},
      {"GIT_TERMINAL_PROMPT", "0"},
      {"SYMPHONIA_GIT_TOKEN", token}
    ]
  end

  defp clean_git_error(output) do
    output
    |> to_string()
    |> String.replace(~r/x-access-token:[^@\s]+@/, "x-access-token:[redacted]@")
    |> String.trim()
    |> case do
      "" -> "Git command failed."
      message -> message
    end
  end

  defp slug(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9._-]/, "-")
    |> String.trim("-")
    |> case do
      "" -> "task"
      slug -> slug
    end
  end

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")
end
