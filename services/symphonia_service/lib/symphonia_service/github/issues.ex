defmodule SymphoniaService.GitHub.Issues do
  @moduledoc """
  Linked GitHub issue updates for completed PR-backed tasks.
  """

  alias SymphoniaService.GitHub.Client

  def close_linked_issue(token, github_repo, issue) when is_map(issue) do
    number = issue["number"]

    if is_nil(number) do
      {:ok, nil}
    else
      owner = issue["owner"] || github_repo["owner"]
      repo = issue["repo"] || github_repo["name"]

      client().update_issue(token, owner, repo, number, %{
        "state" => "closed",
        "state_reason" => "completed"
      })
    end
  end

  def close_linked_issue(_token, _github_repo, _issue), do: {:ok, nil}

  defp client do
    Application.get_env(:symphonia_service, :github_client, Client)
  end
end
