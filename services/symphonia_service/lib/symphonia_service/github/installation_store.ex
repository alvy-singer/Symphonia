defmodule SymphoniaService.GitHub.InstallationStore do
  @moduledoc """
  Plain local storage for GitHub App installation metadata.

  Installation metadata is not a credential. Tokens stay in the installation
  token cache and are never stored here.
  """

  alias SymphoniaService.GitHub.Home

  @store_file "installations.json"

  def load(opts \\ []) do
    path = path(opts)

    case File.read(path) do
      {:ok, ""} -> empty()
      {:ok, body} -> normalize(JSON.decode!(body))
      {:error, :enoent} -> empty()
      {:error, reason} -> raise File.Error, reason: reason, action: "read file", path: path
    end
  end

  def save(state, opts \\ []) when is_map(state) do
    path = path(opts)
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, JSON.encode!(normalize(state)))
    chmod_private(path)
    normalize(state)
  end

  def upsert_installation(installation, opts \\ []) when is_map(installation) do
    state = load(opts)
    id = installation_id(installation)

    installations =
      state["installations"]
      |> Enum.reject(&(installation_id(&1) == id))
      |> Kernel.++([normalize_installation(installation)])
      |> Enum.sort_by(&installation_id/1)

    save(%{"installations" => installations, "updated_at" => now()}, opts)
  end

  def installations(opts \\ []), do: load(opts)["installations"]

  def repositories(opts \\ []) do
    opts
    |> installations()
    |> Enum.flat_map(fn installation ->
      installation_id = installation_id(installation)
      account_login = get_in(installation, ["account", "login"])
      account_type = get_in(installation, ["account", "type"])

      Enum.map(installation["repositories"] || [], fn repo ->
        repo
        |> Map.put_new("installationId", installation_id)
        |> Map.put_new("installation_id", installation_id)
        |> Map.put_new("accountLogin", account_login)
        |> Map.put_new("accountType", account_type)
      end)
    end)
  end

  def find_repository(owner, name, opts \\ []) do
    owner = normalize_part(owner)
    name = normalize_part(name)

    Enum.find(repositories(opts), fn repo ->
      normalize_part(repo["owner"]) == owner and normalize_part(repo["name"]) == name
    end)
  end

  def installed_repository_count(opts \\ []), do: repositories(opts) |> length()

  def public_state(opts \\ []) do
    installations = installations(opts)
    repositories = repositories(opts)

    %{
      "installed" => installations != [],
      "installations" => Enum.map(installations, &public_installation/1),
      "installedRepositoriesCount" => length(repositories),
      "repositories" => Enum.map(repositories, &public_repository/1)
    }
  end

  defp public_installation(installation) do
    %{
      "id" => installation_id(installation),
      "account" => installation["account"],
      "repositorySelection" => installation["repository_selection"],
      "repositoryCount" => length(installation["repositories"] || []),
      "updatedAt" => installation["updated_at"]
    }
    |> reject_nil()
  end

  defp public_repository(repo) do
    %{
      "owner" => repo["owner"],
      "name" => repo["name"],
      "fullName" => repo["full_name"] || full_name(repo),
      "repoId" => repo["repo_id"],
      "url" => repo["url"],
      "cloneUrl" => repo["clone_url"],
      "defaultBranch" => repo["default_branch"],
      "installationId" => repo["installationId"] || repo["installation_id"],
      "accountLogin" => repo["accountLogin"],
      "accountType" => repo["accountType"]
    }
    |> reject_nil()
  end

  defp normalize(%{"installations" => installations} = state) when is_list(installations) do
    %{
      "installations" => Enum.map(installations, &normalize_installation/1),
      "updated_at" => state["updated_at"]
    }
    |> reject_nil()
  end

  defp normalize(_state), do: empty()

  defp normalize_installation(installation) do
    %{
      "id" => installation_id(installation),
      "account" => normalize_account(installation["account"]),
      "repository_selection" =>
        installation["repository_selection"] || installation["repositorySelection"],
      "repositories" => Enum.map(installation["repositories"] || [], &normalize_repository/1),
      "setup_action" => installation["setup_action"] || installation["setupAction"],
      "updated_at" => installation["updated_at"] || installation["updatedAt"] || now()
    }
    |> reject_nil()
  end

  defp normalize_account(nil), do: nil

  defp normalize_account(account) do
    %{
      "login" => account["login"],
      "type" => account["type"],
      "url" => account["html_url"] || account["url"]
    }
    |> reject_nil()
  end

  defp normalize_repository(repo) do
    owner = owner_login(repo)
    name = repo["name"]

    %{
      "owner" => owner,
      "name" => name,
      "full_name" => repo["full_name"] || if(owner && name, do: "#{owner}/#{name}"),
      "repo_id" => repo["id"] || repo["repo_id"] || repo["repoId"],
      "url" => repo["html_url"] || repo["url"],
      "clone_url" => repo["clone_url"] || repo["cloneUrl"],
      "default_branch" => repo["default_branch"] || repo["defaultBranch"]
    }
    |> reject_nil()
  end

  defp owner_login(%{"owner" => %{"login" => login}}), do: login
  defp owner_login(%{"owner" => owner}) when is_binary(owner), do: owner
  defp owner_login(_repo), do: nil

  defp installation_id(installation) do
    installation["id"] || installation["installation_id"] || installation["installationId"]
  end

  defp full_name(repo) do
    if repo["owner"] && repo["name"], do: "#{repo["owner"]}/#{repo["name"]}"
  end

  defp empty, do: %{"installations" => []}
  defp path(opts), do: Path.join(Home.path(opts), @store_file)
  defp normalize_part(value), do: value |> to_string() |> String.downcase()
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp reject_nil(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()

  defp chmod_private(path) do
    File.chmod(path, 0o600)
    :ok
  rescue
    _ -> :ok
  end
end
