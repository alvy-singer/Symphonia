defmodule SymphoniaService.GitHub.Sync do
  @moduledoc """
  Narrow PR lifecycle sync for Milestone 3.
  """

  alias SymphoniaService.GitHub.PullRequests

  def refresh_pull_request(repository, task_key) do
    PullRequests.refresh(repository, task_key)
  end
end
