defmodule SymphoniaService.GitHub.Remote do
  @moduledoc """
  Detects GitHub remotes from local Git repositories.
  """

  def detect(repository) do
    repository["path"]
    |> origin_url()
    |> case do
      nil -> nil
      url -> parse(url)
    end
  end

  def parse(nil), do: nil

  def parse(url) when is_binary(url) do
    url = String.trim(url)

    captures =
      [
        ~r/^https:\/\/github\.com\/(?<owner>[^\/:]+)\/(?<repo>[^\/]+?)(?:\.git)?$/,
        ~r/^git@github\.com:(?<owner>[^\/:]+)\/(?<repo>[^\/]+?)(?:\.git)?$/,
        ~r/^ssh:\/\/git@github\.com\/(?<owner>[^\/:]+)\/(?<repo>[^\/]+?)(?:\.git)?$/
      ]
      |> Enum.find_value(&Regex.named_captures(&1, url))

    case captures do
      %{"owner" => owner, "repo" => repo} ->
        %{
          "owner" => owner,
          "name" => repo,
          "url" => "https://github.com/#{owner}/#{repo}",
          "remoteUrl" => url,
          "defaultBranch" => default_branch_from_remote(url)
        }

      _ ->
        nil
    end
  end

  def default_branch(repository) do
    repository["path"]
    |> git(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"])
    |> case do
      nil ->
        git(repository["path"], ["branch", "--show-current"]) || "main"

      "origin/" <> branch ->
        branch

      branch ->
        branch
    end
  end

  defp origin_url(path) do
    git(path, ["remote", "get-url", "origin"])
  end

  defp git(path, args) do
    case System.find_executable("git") do
      nil ->
        nil

      _git ->
        case System.cmd("git", ["-C", path | args], stderr_to_stdout: true) do
          {output, 0} -> String.trim(output)
          _ -> nil
        end
    end
  rescue
    _ -> nil
  end

  defp default_branch_from_remote(_url), do: nil
end
