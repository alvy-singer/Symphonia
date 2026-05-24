defmodule SymphoniaService.GitHub.RepositoryLink do
  @moduledoc """
  Links a local Symphonia repository registry entry to an accessible GitHub repo.
  """

  alias SymphoniaService.RepositoryRegistry

  alias SymphoniaService.GitHub.{
    Auth,
    Client,
    DeviceAuth,
    InstallationStore,
    Remote,
    Repositories
  }

  def state(repository) do
    %{
      "connection" => Auth.connection(),
      "detectedRemote" => Remote.detect(repository),
      "link" => link(repository),
      "access" => access_state(repository)
    }
  end

  def accessible_repositories, do: Repositories.accessible_repositories()

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

    case installed_or_fallback_repo(owner, name) do
      {:ok, github_repo} ->
        github =
          %{
            "owner" => owner_login(github_repo) || owner,
            "name" => github_repo["name"] || name,
            "repo_id" => github_repo["id"],
            "url" =>
              github_repo["html_url"] || github_repo["url"] ||
                "https://github.com/#{owner}/#{name}",
            "clone_url" => github_repo["clone_url"] || github_repo["cloneUrl"],
            "default_branch" =>
              github_repo["default_branch"] || github_repo["defaultBranch"] ||
                Remote.default_branch(repository),
            "installation_id" =>
              github_repo["installationId"] || github_repo["installation_id"] ||
                Map.get(attrs, "installationId") || Map.get(attrs, "installation_id"),
            "auth_mode" => github_repo["authMode"] || "app_installation",
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
                "Symphonía is not installed on this GitHub repository yet."
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
          "authMode" => github["auth_mode"],
          "linkedAt" => github["linked_at"]
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      _ ->
        nil
    end
  end

  defp installed_or_fallback_repo(owner, name) do
    case InstallationStore.find_repository(owner, name) do
      nil ->
        fallback_repo(owner, name)

      repo ->
        {:ok,
         %{
           "owner" => repo["owner"],
           "name" => repo["name"],
           "id" => repo["repoId"] || repo["repo_id"],
           "html_url" => repo["url"],
           "clone_url" => repo["cloneUrl"] || repo["clone_url"],
           "default_branch" => repo["defaultBranch"] || repo["default_branch"],
           "installation_id" => repo["installationId"] || repo["installation_id"],
           "authMode" => "app_installation"
         }}
    end
  end

  defp fallback_repo(owner, name) do
    if DeviceAuth.enabled?() do
      token = Auth.user_token!()

      case client().get_repository(token, owner, name) do
        {:ok, repo} -> {:ok, Map.put(repo, "authMode", "device_user_token")}
        {:error, payload} -> {:error, payload}
      end
    else
      {:error, %{"message" => "Symphonía is not installed on this GitHub repository yet."}}
    end
  end

  defp owner_login(%{"owner" => %{"login" => login}}), do: login
  defp owner_login(%{"owner" => owner}) when is_binary(owner), do: owner
  defp owner_login(_repo), do: nil

  defp access_state(repository) do
    remote = Remote.detect(repository)
    link = link(repository)

    cond do
      link ->
        %{"state" => "linked", "message" => "GitHub linked"}

      is_nil(remote) ->
        %{"state" => "no_remote", "message" => "GitHub remote was not detected."}

      InstallationStore.find_repository(remote["owner"], remote["name"]) ->
        %{"state" => "available", "message" => "GitHub App access available"}

      true ->
        %{
          "state" => "missing",
          "message" =>
            "Install the Symphonía GitHub App on this repository to open pull requests."
        }
    end
  end

  defp client do
    Application.get_env(:symphonia_service, :github_client, Client)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
