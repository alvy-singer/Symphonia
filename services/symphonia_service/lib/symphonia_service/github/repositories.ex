defmodule SymphoniaService.GitHub.Repositories do
  @moduledoc """
  Installed GitHub repository listing and installation completion.
  """

  alias SymphoniaService.GitHub.{
    AppAuth,
    Client,
    InstallationStore,
    InstallationToken
  }

  @per_page 100

  def accessible_repositories do
    %{"repositories" => InstallationStore.public_state()["repositories"]}
  end

  def complete_installation(params) do
    installation_id =
      Map.get(params, "installation_id") ||
        Map.get(params, "installationId") ||
        raise ArgumentError, "GitHub installation ID is required."

    refresh_installation(installation_id, params)
  end

  def refresh_installations(params \\ %{}) do
    case Map.get(params, "installation_id") || Map.get(params, "installationId") do
      id when is_binary(id) and id != "" ->
        refresh_installation(id, params)

      id when is_integer(id) ->
        refresh_installation(id, params)

      _ ->
        InstallationStore.installations()
        |> Enum.each(fn installation ->
          installation["id"] |> refresh_installation(%{})
        end)

        InstallationStore.public_state()
    end
  end

  def refresh_installation(installation_id, params \\ %{}) do
    jwt = AppAuth.jwt()
    installation = installation_metadata(jwt, installation_id)
    token = InstallationToken.refresh!(installation_id)["token"]
    repositories = list_installation_repositories(token)

    InstallationStore.upsert_installation(%{
      "id" => installation_id,
      "account" => installation["account"] || account_from_repositories(repositories),
      "repository_selection" => installation["repository_selection"],
      "repositories" => repositories,
      "setup_action" => Map.get(params, "setup_action") || Map.get(params, "setupAction")
    })

    InstallationStore.public_state()
  end

  def list_installation_repositories(token) do
    list_installation_repositories(token, 1, [])
  end

  defp list_installation_repositories(token, page, acc) do
    case client().list_installation_repositories(token, page, @per_page) do
      {:ok, %{"repositories" => repos} = payload} ->
        next = acc ++ repos
        total = payload["total_count"]

        cond do
          is_integer(total) and length(next) >= total ->
            Enum.map(next, &normalize_repository/1)

          length(repos) < @per_page ->
            Enum.map(next, &normalize_repository/1)

          true ->
            list_installation_repositories(token, page + 1, next)
        end

      {:error, payload} ->
        raise ArgumentError,
              Map.get(payload, "message", "Could not list GitHub installation repositories.")
    end
  end

  defp installation_metadata(jwt, installation_id) do
    case client().get_app_installation(jwt, installation_id) do
      {:ok, installation} -> installation
      {:error, _payload} -> %{}
    end
  end

  defp normalize_repository(repo) do
    owner = get_in(repo, ["owner", "login"]) || repo["owner"]
    name = repo["name"]

    %{
      "owner" => owner,
      "name" => name,
      "full_name" => repo["full_name"] || if(owner && name, do: "#{owner}/#{name}"),
      "repo_id" => repo["id"],
      "url" => repo["html_url"],
      "clone_url" => repo["clone_url"],
      "default_branch" => repo["default_branch"]
    }
    |> reject_nil()
  end

  defp account_from_repositories([repo | _]) do
    case get_in(repo, ["owner"]) do
      owner when is_binary(owner) -> %{"login" => owner}
      _ -> nil
    end
  end

  defp account_from_repositories(_repositories), do: nil

  defp client do
    Application.get_env(:symphonia_service, :github_client, Client)
  end

  defp reject_nil(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
end
