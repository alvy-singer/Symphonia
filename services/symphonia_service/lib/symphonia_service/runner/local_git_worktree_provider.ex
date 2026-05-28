defmodule SymphoniaService.Runner.LocalGitWorktreeProvider do
  @moduledoc """
  Local persistent Git worktree workspace provider.

  Release is intentionally non-destructive so daemon retries keep the existing
  task workspace on disk.
  """

  @behaviour SymphoniaService.Runner.WorkspaceProvider

  alias SymphoniaService.CodingAssistant.BranchManager

  @impl true
  def prepare(repository, task, _run, _opts) do
    {:ok, BranchManager.prepare_persistent_task_branch_worktree!(repository, task)}
  rescue
    error -> {:error, Exception.message(error)}
  end

  @impl true
  def release(context, _opts) do
    BranchManager.release_persistent_task_branch_worktree(context)
    :ok
  end
end
