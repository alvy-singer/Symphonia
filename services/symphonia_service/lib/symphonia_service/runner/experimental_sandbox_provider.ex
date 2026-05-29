defmodule SymphoniaService.Runner.ExperimentalSandboxProvider do
  @moduledoc """
  Experimental local fake sandbox workspace provider.

  The sandbox workspace is execution scratch only. Review branch authority stays
  with the local persistent task worktree returned as `review_context`.
  """

  @behaviour SymphoniaService.Runner.WorkspaceProvider

  alias SymphoniaService.Runner.LocalGitWorktreeProvider

  @impl true
  def prepare(repository, task, run, params) do
    with {:ok, review_context} <- LocalGitWorktreeProvider.prepare(repository, task, run, params),
         {:ok, sandbox} <- clone_review_workspace(review_context, task) do
      {:ok, sandbox_context(review_context, sandbox)}
    else
      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  @impl true
  def release(context, run) do
    context
    |> private_value(:sandbox_path)
    |> remove_sandbox_path()

    review_context =
      Map.get(context, :review_context) ||
        Map.get(context, "review_context")

    LocalGitWorktreeProvider.release(review_context, run)

    :ok
  rescue
    _error -> :ok
  end

  defp clone_review_workspace(review_context, task) do
    sandbox_id = sandbox_id(task)
    root = sandbox_root()
    sandbox_root = Path.join(root, sandbox_id)
    sandbox_path = Path.join(sandbox_root, "repo")
    events_path = Path.join(sandbox_root, "events.jsonl")

    File.rm_rf(sandbox_root)
    File.mkdir_p!(sandbox_root)

    with :ok <- git(["clone", "--no-hardlinks", review_context.repo_path, sandbox_path]),
         :ok <- git(["-C", sandbox_path, "checkout", "-B", review_context.head_branch]) do
      {:ok,
       %{
         sandbox_id: sandbox_id,
         sandbox_path: sandbox_path,
         sandbox_events_path: events_path
       }}
    else
      {:error, reason} ->
        File.rm_rf(sandbox_root)
        LocalGitWorktreeProvider.release(review_context, %{})
        {:error, reason}
    end
  end

  defp sandbox_context(review_context, sandbox) do
    %{
      base_branch: review_context.base_branch,
      head_branch: review_context.head_branch,
      remote_url: review_context.remote_url,
      repo_path: sandbox.sandbox_path,
      source_repo_path: review_context.source_repo_path,
      persistent: false,
      workspace_provider: "experimental_sandbox",
      shell_transport: "local_fake_sandbox",
      review_context: review_context,
      private: %{
        sandbox_id: sandbox.sandbox_id,
        sandbox_path: sandbox.sandbox_path,
        sandbox_events_path: sandbox.sandbox_events_path
      }
    }
  end

  defp git(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _status} -> {:error, clean_git_error(output)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp remove_sandbox_path(nil), do: :ok

  defp remove_sandbox_path(path) when is_binary(path) do
    sandbox_root = Path.dirname(path)
    if sandbox_child?(sandbox_root), do: File.rm_rf(sandbox_root)
    :ok
  end

  defp remove_sandbox_path(_path), do: :ok

  defp private_value(context, key) do
    private = Map.get(context, :private) || Map.get(context, "private") || %{}
    Map.get(private, key) || Map.get(private, Atom.to_string(key))
  end

  defp sandbox_child?(path) do
    path = Path.expand(path)
    root = Path.expand(sandbox_root())
    path == root or String.starts_with?(path, root <> "/")
  end

  defp sandbox_root do
    System.get_env("SYMPHONIA_SANDBOXES_ROOT") ||
      Path.join(System.tmp_dir!(), "symphonia-experimental-sandboxes")
  end

  defp sandbox_id(task) do
    key =
      task["key"]
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9._-]/, "-")
      |> String.trim("-")
      |> case do
        "" -> "task"
        value -> value
      end

    "sandbox_#{key}_#{System.unique_integer([:positive])}"
  end

  defp clean_git_error(output) do
    output
    |> to_string()
    |> String.replace(~r/x-access-token:[^@\s]+@/, "x-access-token:[redacted]@")
    |> String.trim()
    |> case do
      "" -> "Sandbox workspace preparation failed."
      _message -> "Sandbox workspace preparation failed."
    end
  end
end
