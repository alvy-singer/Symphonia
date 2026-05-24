defmodule SymphoniaService.GitHub.RepositoryLink do
  @moduledoc """
  Links a local Symphonia repository registry entry to an accessible GitHub repo.
  """

  alias SymphoniaService.RepositoryRegistry
  alias SymphoniaService.GitHub.{Auth, Client, Remote}

  def state(repository) do
    %{
      "connection" => Auth.connection(),
      "detectedRemote" => Remote.detect(repository),
      "link" => link(repository)
    }
  end

  def accessible_repositories do
    token = Auth.user_token!()

    with {:ok, %{"installations" => installations}} <- client().list_installations(token) do
      repositories =
        installations
        |> Enum.flat_map(&repositories_for_installation(token, &1))

      %{"repositories" => repositories}
    end
  end

  def link(registry_path, repository, attrs) do
    remote = Remote.detect(repository) || %{}

    owner =
      Map.get(attrs, "owner") ||
        Map.get(attrs, "repoOwner") ||
        remote["owner"] ||
        raise ArgumentError, "GitHub remote was not detected for this repository."

    name =
      Map.get(attrs, "name") ||
        Map.get(attrs, "repo") ||
        remote["name"] ||
        raise ArgumentError, "GitHub remote was not detected for this repository."

    token = Auth.user_token!()

    case client().get_repository(token, owner, name) do
      {:ok, github_repo} ->
        github =
          %{
            "owner" => get_in(github_repo, ["owner", "login"]) || owner,
            "name" => github_repo["name"] || name,
            "repo_id" => github_repo["id"],
            "url" => github_repo["html_url"] || "https://github.com/#{owner}/#{name}",
            "clone_url" => github_repo["clone_url"],
            "default_branch" =>
              github_repo["default_branch"] || Remote.default_branch(repository),
            "installation_id" =>
              Map.get(attrs, "installationId") || Map.get(attrs, "installation_id"),
            "linked_at" => now()
          }
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()

        updated =
          RepositoryRegistry.update(registry_path, repository["key"], fn repo ->
            Map.put(repo, "github", github)
          end)

        %{"link" => link(updated), "detectedRemote" => Remote.detect(updated)}

      {:error, payload} ->
        raise ArgumentError,
              Map.get(
                payload,
                "message",
                "GitHub repository is not accessible. Install Symphonía on this repository and try again."
              )
    end
  end

  def link(repository) do
    case repository["github"] do
      github when is_map(github) ->
        %{
          "owner" => github["owner"],
          "name" => github["name"],
          "repoId" => github["repo_id"],
          "url" => github["url"],
          "cloneUrl" => github["clone_url"],
          "defaultBranch" => github["default_branch"],
          "installationId" => github["installation_id"],
          "linkedAt" => github["linked_at"]
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      _ ->
        nil
    end
  end

  defp repositories_for_installation(token, installation) do
    installation_id = installation["id"]
    account_login = get_in(installation, ["account", "login"])
    account_type = get_in(installation, ["account", "type"])

    case client().list_installation_repositories(token, installation_id) do
      {:ok, %{"repositories" => repos}} ->
        Enum.map(repos, fn repo ->
          %{
            "owner" => get_in(repo, ["owner", "login"]),
            "name" => repo["name"],
            "repoId" => repo["id"],
            "url" => repo["html_url"],
            "cloneUrl" => repo["clone_url"],
            "defaultBranch" => repo["default_branch"],
            "installationId" => installation_id,
            "accountLogin" => account_login,
            "accountType" => account_type
          }
        end)

      _ ->
        []
    end
  end

  defp client do
    Application.get_env(:symphonia_service, :github_client, Client)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
