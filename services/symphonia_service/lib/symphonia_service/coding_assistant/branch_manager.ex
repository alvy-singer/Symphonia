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
    head_branch = "symphonia/task/#{slug(task["key"])}"
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

  defp github_repo!(repository) do
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

  defp fetch_base!(repo_path, remote_url, base_branch, askpass) do
    ref = "refs/heads/#{base_branch}:refs/remotes/symphonia/#{base_branch}"
    git!(repo_path, ["fetch", "--depth=1", remote_url, ref], askpass)
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
    git!(
      repo_path,
      ["push", "--force-with-lease", remote_url, "HEAD:refs/heads/#{head_branch}"],
      askpass
    )
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
    askpass = askpass_path()

    File.write!(askpass, """
    #!/bin/sh
    case "$1" in
      *Username*) echo x-access-token ;;
      *) printf '%s\\n' "$SYMPHONIA_GIT_TOKEN" ;;
    esac
    """)

    File.chmod(askpass, 0o700)

    auth = %{askpass: askpass, token: token}

    try do
      fun.(auth)
    after
      File.rm(askpass)
    end
  end

  defp askpass_path do
    Path.join(System.tmp_dir!(), "symphonia-git-askpass-#{System.unique_integer([:positive])}.sh")
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
