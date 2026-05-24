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
    |> normalize_key()
    |> String.slice(0, 3)
    |> case do
      "" -> "REP"
      key -> key
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
end
