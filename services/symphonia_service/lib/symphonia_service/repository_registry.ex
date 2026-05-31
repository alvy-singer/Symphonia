defmodule SymphoniaService.RepositoryRegistry do
  @moduledoc """
  Private local registry for repositories Symphonia can open.

  The registry is intentionally outside any managed repository. Repository
  Markdown remains source-of-truth for workspace objects; this file only maps
  stable repo keys to absolute local paths.
  """

  @git_error "This folder is not a Git repository. Choose a repository folder, or initialize Git in this folder before adding it to Symphonía."

  def default_path do
    System.get_env("SYMPHONIA_REGISTRY_PATH") ||
      Path.join([System.user_home!(), ".symphonia", "repositories.json"])
  end

  def git_error, do: @git_error

  def list(registry_path \\ default_path()) do
    registry_path
    |> read()
    |> Map.get("repositories", [])
    |> Enum.map(&normalize_repository/1)
    |> Enum.sort_by(&String.downcase(&1["key"]))
  end

  def get(registry_path, key) do
    normalized_key = normalize_key(key)
    Enum.find(list(registry_path), &(&1["key"] == normalized_key))
  end

  def get!(registry_path, key) do
    case get(registry_path, key) do
      nil -> raise ArgumentError, "Repository #{normalize_key(key)} is not registered."
      repository -> repository
    end
  end

  def add(registry_path, attrs) when is_map(attrs) do
    raw_path = Map.get(attrs, "path") || Map.get(attrs, :path)
    repo_path = validate_repository_path!(raw_path)
    repositories = list(registry_path)

    case Enum.find(repositories, &same_path?(&1["path"], repo_path)) do
      nil ->
        manual_key? = present?(Map.get(attrs, "key") || Map.get(attrs, :key))
        requested_key = key_from_attrs(attrs, repo_path)
        key = available_key!(repositories, requested_key, manual_key?)

        repository =
          %{
            "key" => key,
            "name" => name_from_attrs(attrs, repo_path),
            "path" => repo_path,
            "last_task_number" => 0
          }
          |> normalize_repository()

        save(registry_path, repositories ++ [repository])
        repository

      existing ->
        existing
    end
  end

  def add_github(registry_path, attrs) when is_map(attrs) do
    {owner, name} = github_owner_and_name!(attrs)
    repositories = list(registry_path)

    case Enum.find(repositories, &same_github_repo?(&1, owner, name)) do
      nil ->
        repo_path = github_workspace_path(registry_path, owner, name)
        File.mkdir_p!(repo_path)
        ensure_managed_git_repo(repo_path, github_clone_url(attrs, owner, name))

        manual_key? = present?(Map.get(attrs, "key") || Map.get(attrs, :key))

        requested_key =
          Map.get(attrs, "key", Map.get(attrs, :key))
          |> case do
            value when is_binary(value) and value != "" -> normalize_key(value)
            _ -> derive_key_from_name(name)
          end

        key = available_key!(repositories, requested_key, manual_key?)

        repository =
          %{
            "key" => key,
            "name" => github_full_name(attrs, owner, name),
            "path" => repo_path,
            "last_task_number" => 0,
            "github" => github_attrs(attrs, owner, name)
          }
          |> normalize_repository()

        save(registry_path, repositories ++ [repository])
        repository

      existing ->
        existing
    end
  end

  def update(registry_path, key, fun) when is_function(fun, 1) do
    normalized_key = normalize_key(key)
    repositories = list(registry_path)

    {updated, changed?} =
      Enum.map_reduce(repositories, false, fn repository, changed ->
        if repository["key"] == normalized_key do
          next = repository |> fun.() |> normalize_repository()
          {next, true}
        else
          {repository, changed}
        end
      end)

    if changed? do
      save(registry_path, updated)
      get!(registry_path, normalized_key)
    else
      raise ArgumentError, "Repository #{normalized_key} is not registered."
    end
  end

  def remove(registry_path, key) do
    normalized_key = normalize_key(key)
    repositories = list(registry_path)
    {removed, kept} = Enum.split_with(repositories, &(&1["key"] == normalized_key))

    case removed do
      [repository] ->
        save(registry_path, kept)
        repository

      [] ->
        raise ArgumentError, "Repository #{normalized_key} is not registered."
    end
  end

  defp read(registry_path) do
    case File.read(registry_path) do
      {:ok, ""} ->
        %{"repositories" => []}

      {:ok, body} ->
        JSON.decode!(body)

      {:error, :enoent} ->
        %{"repositories" => []}

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read file", path: registry_path
    end
  end

  defp save(registry_path, repositories) do
    registry_path |> Path.dirname() |> File.mkdir_p!()
    File.write!(registry_path, JSON.encode!(%{"repositories" => repositories}))
  end

  defp validate_repository_path!(nil), do: raise(ArgumentError, "Repository path is required.")
  defp validate_repository_path!(""), do: raise(ArgumentError, "Repository path is required.")

  defp validate_repository_path!(path) when is_binary(path) do
    expanded = Path.expand(path)

    cond do
      not File.dir?(expanded) ->
        raise ArgumentError, "Repository path does not exist or is not a directory."

      not git_repository?(expanded) ->
        raise ArgumentError, @git_error

      true ->
        expanded
    end
  end

  defp git_repository?(path) do
    File.exists?(Path.join(path, ".git")) or git_rev_parse?(path, "--is-inside-work-tree") or
      git_rev_parse?(path, "--is-bare-repository")
  end

  defp git_rev_parse?(path, flag) do
    case System.find_executable("git") do
      nil ->
        false

      _git ->
        case System.cmd("git", ["-C", path, "rev-parse", flag], stderr_to_stdout: true) do
          {"true\n", 0} -> true
          {"true", 0} -> true
          _ -> false
        end
    end
  rescue
    _ -> false
  end

  defp key_from_attrs(attrs, repo_path) do
    attrs
    |> Map.get("key", Map.get(attrs, :key))
    |> case do
      value when is_binary(value) and value != "" -> normalize_key(value)
      _ -> derive_key(repo_path)
    end
  end

  defp name_from_attrs(attrs, repo_path) do
    case Map.get(attrs, "name", Map.get(attrs, :name)) do
      value when is_binary(value) and value != "" -> String.trim(value)
      _ -> Path.basename(repo_path)
    end
  end

  defp available_key!(repositories, requested_key, true) do
    if Enum.any?(repositories, &(&1["key"] == requested_key)) do
      raise ArgumentError, "Repository key #{requested_key} is already registered."
    end

    requested_key
  end

  defp available_key!(repositories, requested_key, false) do
    used = MapSet.new(Enum.map(repositories, & &1["key"]))

    Stream.iterate(0, &(&1 + 1))
    |> Enum.find_value(fn
      0 ->
        if MapSet.member?(used, requested_key), do: nil, else: requested_key

      n ->
        candidate = "#{requested_key}#{n + 1}"
        if MapSet.member?(used, candidate), do: nil, else: candidate
    end)
  end

  defp derive_key(repo_path) do
    repo_path
    |> Path.basename()
    |> derive_key_from_name()
  end

  defp derive_key_from_name(name) do
    name
    |> normalize_key()
    |> String.slice(0, 3)
    |> case do
      "" -> "REP"
      key -> key
    end
  end

  defp github_owner_and_name!(attrs) do
    owner = string_from_attrs(attrs, "owner") || string_from_attrs(attrs, "repoOwner")
    name = string_from_attrs(attrs, "name") || string_from_attrs(attrs, "repo")

    cond do
      present?(owner) and present?(name) ->
        {owner, name}

      full_name = string_from_attrs(attrs, "fullName") ->
        case String.split(full_name, "/", parts: 2) do
          [full_owner, full_repo] when full_owner != "" and full_repo != "" ->
            {full_owner, full_repo}

          _ ->
            raise ArgumentError, "GitHub repository is required."
        end

      true ->
        raise ArgumentError, "GitHub repository is required."
    end
  end

  defp github_workspace_path(registry_path, owner, name) do
    root =
      System.get_env("SYMPHONIA_GITHUB_WORKSPACES_ROOT") ||
        Path.join(Path.dirname(registry_path), "github-workspaces")

    Path.join([root, safe_path_part(owner), safe_path_part(name)])
  end

  defp safe_path_part(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9._-]/, "-")
    |> case do
      "" -> "repo"
      part -> part
    end
  end

  defp ensure_managed_git_repo(repo_path, clone_url) do
    case System.find_executable("git") do
      nil ->
        File.mkdir_p!(Path.join(repo_path, ".git"))

      _git ->
        unless git_repository?(repo_path) do
          System.cmd("git", ["-C", repo_path, "init"], stderr_to_stdout: true)
        end

        if present?(clone_url) do
          case System.cmd("git", ["-C", repo_path, "remote", "get-url", "origin"],
                 stderr_to_stdout: true
               ) do
            {_output, 0} ->
              System.cmd("git", ["-C", repo_path, "remote", "set-url", "origin", clone_url],
                stderr_to_stdout: true
              )

            _ ->
              System.cmd("git", ["-C", repo_path, "remote", "add", "origin", clone_url],
                stderr_to_stdout: true
              )
          end
        end
    end

    :ok
  rescue
    _ ->
      File.mkdir_p!(Path.join(repo_path, ".git"))
      :ok
  end

  defp github_attrs(attrs, owner, name) do
    %{
      "owner" => owner,
      "name" => name,
      "repo_id" =>
        Map.get(attrs, "repoId") || Map.get(attrs, "repo_id") || Map.get(attrs, :repo_id),
      "url" => string_from_attrs(attrs, "url") || "https://github.com/#{owner}/#{name}",
      "clone_url" => github_clone_url(attrs, owner, name),
      "default_branch" =>
        string_from_attrs(attrs, "defaultBranch") || string_from_attrs(attrs, "default_branch"),
      "installation_id" =>
        Map.get(attrs, "installationId") ||
          Map.get(attrs, "installation_id") ||
          Map.get(attrs, :installation_id),
      "auth_mode" => "app_installation",
      "linked_at" => now()
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp github_clone_url(attrs, owner, name) do
    string_from_attrs(attrs, "cloneUrl") ||
      string_from_attrs(attrs, "clone_url") ||
      "https://github.com/#{owner}/#{name}.git"
  end

  defp github_full_name(attrs, owner, name) do
    string_from_attrs(attrs, "fullName") || "#{owner}/#{name}"
  end

  defp same_github_repo?(repository, owner, name) do
    case repository["github"] do
      github when is_map(github) ->
        String.downcase(to_string(github["owner"])) == String.downcase(owner) and
          String.downcase(to_string(github["name"])) == String.downcase(name)

      _ ->
        false
    end
  end

  defp string_from_attrs(attrs, key) do
    case Map.get(attrs, key) || Map.get(attrs, String.to_atom(key)) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: nil, else: value

      _ ->
        nil
    end
  end

  defp normalize_repository(repository) do
    normalized = %{
      "key" => normalize_key(repository["key"]),
      "name" => repository["name"] || Path.basename(repository["path"] || ""),
      "path" => Path.expand(repository["path"]),
      "last_task_number" => integer(repository["last_task_number"])
    }

    case repository["github"] do
      github when is_map(github) -> Map.put(normalized, "github", github)
      _ -> normalized
    end
    |> maybe_put_map("automation", repository["automation"])
    |> maybe_put_boolean("remoteExecutionAllowed", remote_execution_allowed?(repository))
    |> maybe_put_boolean("sandboxExecutionAllowed", sandbox_execution_allowed?(repository))
    |> maybe_put_string("sandboxProvider", sandbox_provider(repository))
    |> maybe_put_list(
      "allowedRunnerIds",
      repository["allowedRunnerIds"] || repository["allowed_runner_ids"]
    )
    |> maybe_put_list(
      "allowedSandboxProviders",
      repository["allowedSandboxProviders"] || repository["allowed_sandbox_providers"]
    )
    |> maybe_put_list(
      "allowedCodingAssistantProviders",
      repository["allowedCodingAssistantProviders"] ||
        repository["allowed_coding_assistant_providers"]
    )
    |> maybe_put_list(
      "secretScopesAllowed",
      repository["secretScopesAllowed"] || repository["secret_scopes_allowed"]
    )
    |> Map.put("requireTrustedRunner", true)
  end

  defp maybe_put_map(map, key, value) when is_map(value), do: Map.put(map, key, value)
  defp maybe_put_map(map, _key, _value), do: map
  defp maybe_put_boolean(map, key, value) when is_boolean(value), do: Map.put(map, key, value)
  defp maybe_put_boolean(map, _key, _value), do: map

  defp maybe_put_string(map, key, value) when is_binary(value) and value != "",
    do: Map.put(map, key, value)

  defp maybe_put_string(map, _key, _value), do: map

  defp maybe_put_list(map, key, value) when is_list(value),
    do: Map.put(map, key, Enum.filter(value, &is_binary/1))

  defp maybe_put_list(map, key, _value), do: Map.put_new(map, key, [])

  defp remote_execution_allowed?(repository) do
    repository["remoteExecutionAllowed"] == true or repository["remote_execution_allowed"] == true
  end

  defp sandbox_execution_allowed?(repository) do
    repository["sandboxExecutionAllowed"] == true or
      repository["sandbox_execution_allowed"] == true
  end

  defp sandbox_provider(repository) do
    repository["sandboxProvider"] || repository["sandbox_provider"]
  end

  defp normalize_key(value) when is_binary(value) do
    value
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9]/, "")
    |> case do
      "" -> "REP"
      key -> key
    end
  end

  defp normalize_key(value), do: value |> to_string() |> normalize_key()

  defp integer(value) when is_integer(value), do: value
  defp integer(value) when is_binary(value), do: String.to_integer(value)
  defp integer(_value), do: 0

  defp same_path?(left, right), do: Path.expand(left) == Path.expand(right)

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
