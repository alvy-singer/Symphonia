defmodule SymphoniaService.SpecWorkspace.Store do
  @moduledoc """
  Filesystem store for repo-backed spec artifacts.
  """

  alias SymphoniaService.Markdown
  alias SymphoniaService.SpecWorkspace.{Artifact, Templates}

  @statuses ~w(draft in_discussion requirements_ready plan_ready ready_for_approval approved archived)

  @directories [
    "symphonia/codebase",
    "symphonia/milestones",
    "symphonia/discussions",
    "symphonia/requirements",
    "symphonia/plans",
    "symphonia/decisions",
    "symphonia/tasks",
    "symphonia/reviews",
    "symphonia/run-summaries"
  ]

  @singletons %{
    "codebase_map" => {"codebase-map", "symphonia/codebase/map.md"},
    "codebase_conventions" => {"codebase-conventions", "symphonia/codebase/conventions.md"},
    "codebase_architecture" => {"codebase-architecture", "symphonia/codebase/architecture.md"}
  }

  @collections %{
    "milestone" => {"milestone", "symphonia/milestones"},
    "discussion" => {"discussion", "symphonia/discussions"},
    "requirements" => {"requirements", "symphonia/requirements"},
    "plan" => {"plan", "symphonia/plans"},
    "decision" => {"decision", "symphonia/decisions"}
  }

  def directories, do: @directories
  def statuses, do: @statuses
  def artifact_types, do: Map.keys(@singletons) ++ Map.keys(@collections)
  def singleton_types, do: Map.keys(@singletons)
  def collection_types, do: Map.keys(@collections)

  def state(repository) do
    missing_directories =
      Enum.reject(@directories, fn directory ->
        repository["path"] |> Path.join(directory) |> File.dir?()
      end)

    missing_defaults =
      @singletons
      |> Enum.reject(fn {_type, {_id, relative_path}} ->
        repository["path"] |> Path.join(relative_path) |> File.exists?()
      end)
      |> Enum.map(fn {type, _config} -> type end)
      |> Enum.sort()

    initialized = missing_directories == [] and missing_defaults == []

    %{
      "exists" => spec_files_exist?(repository),
      "initialized" => initialized,
      "missingDirectories" => missing_directories,
      "missingDefaultArtifacts" => missing_defaults,
      "statuses" => @statuses
    }
  end

  def initialize(repository) do
    Enum.each(@directories, fn directory ->
      repository["path"]
      |> Path.join(directory)
      |> File.mkdir_p!()
    end)

    Enum.each(@singletons, fn {type, {id, relative_path}} ->
      path = Path.join(repository["path"], relative_path)

      unless File.exists?(path) do
        write_new_artifact!(path, type, id, %{})
      end
    end)

    state(repository)
  end

  def list_artifacts(repository) do
    artifact_types()
    |> Enum.map(fn type -> {type, list_artifacts(repository, type)} end)
    |> Map.new()
  end

  def list_artifacts(repository, type) do
    validate_type!(type)

    paths =
      case @singletons[type] do
        {_id, relative_path} ->
          [Path.join(repository["path"], relative_path)]

        nil ->
          {_prefix, directory} = Map.fetch!(@collections, type)
          repository["path"] |> Path.join(directory) |> Path.join("*.md") |> Path.wildcard()
      end

    paths
    |> Enum.filter(&File.exists?/1)
    |> Enum.sort()
    |> Enum.map(&read_path(repository, type, &1))
  end

  def read_artifact(repository, type, id) do
    {path, type} = artifact_path!(repository, type, id)
    read_path(repository, type, path)
  end

  def update_artifact(repository, type, id, patch) when is_map(patch) do
    artifact = read_artifact(repository, type, id)
    metadata_patch = Map.get(patch, "metadata", %{})
    body = Map.get(patch, "body", artifact["body"])

    frontmatter =
      artifact["metadata"]
      |> merge_metadata!(type, artifact["id"], metadata_patch)
      |> Map.put("updated_at", now())

    path = Path.join(repository["path"], artifact["path"])
    File.write!(path, Markdown.serialize(frontmatter, body))
    read_path(repository, type, path)
  end

  def create_artifact(repository, type, attrs \\ %{}) do
    validate_collection_type!(type)
    id = next_id(repository, type)
    create_artifact(repository, type, id, attrs)
  end

  def create_artifact(repository, type, id, attrs) do
    validate_collection_type!(type)
    validate_id!(id)
    {_prefix, directory} = Map.fetch!(@collections, type)
    path = Path.join([repository["path"], directory, "#{id}.md"])
    File.mkdir_p!(Path.dirname(path))
    if File.exists?(path), do: raise(ArgumentError, "Artifact already exists.")
    write_new_artifact!(path, type, id, attrs)
    read_path(repository, type, path)
  end

  def create_or_update_artifact(repository, type, id, attrs) when is_map(attrs) do
    validate_collection_type!(type)
    validate_id!(id)
    {_prefix, directory} = Map.fetch!(@collections, type)
    path = Path.join([repository["path"], directory, "#{id}.md"])

    if File.exists?(path) do
      patch = %{"metadata" => Map.drop(attrs, ["body"])}
      patch = if Map.has_key?(attrs, "body"), do: Map.put(patch, "body", attrs["body"]), else: patch
      update_artifact(repository, type, id, patch)
    else
      File.mkdir_p!(Path.dirname(path))
      write_new_artifact!(path, type, id, attrs)
      read_path(repository, type, path)
    end
  end

  def artifact_exists?(repository, type, id) do
    validate_collection_type!(type)
    validate_id!(id)
    {_prefix, directory} = Map.fetch!(@collections, type)
    File.exists?(Path.join([repository["path"], directory, "#{id}.md"]))
  end

  def next_id(repository, type) do
    validate_collection_type!(type)
    {prefix, directory} = Map.fetch!(@collections, type)
    dir = Path.join(repository["path"], directory)

    used =
      dir
      |> Path.join("*.md")
      |> Path.wildcard()
      |> Enum.reduce(MapSet.new(), fn path, used ->
        path
        |> ids_for_file()
        |> Enum.reduce(used, fn id, acc ->
          case number_for_id(id, prefix) do
            nil -> acc
            number -> MapSet.put(acc, number)
          end
        end)
      end)

    number =
      used
      |> MapSet.to_list()
      |> Enum.max(fn -> 0 end)
      |> Kernel.+(1)

    "#{prefix}-#{String.pad_leading(Integer.to_string(number), 3, "0")}"
  end

  defp spec_files_exist?(repository) do
    Enum.any?(@directories, fn directory ->
      File.dir?(Path.join(repository["path"], directory))
    end) or
      Enum.any?(@singletons, fn {_type, {_id, relative_path}} ->
        File.exists?(Path.join(repository["path"], relative_path))
      end)
  end

  defp write_new_artifact!(path, type, id, attrs) do
    validate_status!(Map.get(attrs, "status") || "draft")
    frontmatter = Templates.frontmatter(type, id, attrs)
    body = Map.get(attrs, "body") || Templates.body(type, id, attrs)
    File.write!(path, Markdown.serialize(frontmatter, body))
  end

  defp read_path(repository, type, path) do
    parsed = path |> File.read!() |> Markdown.parse()
    Artifact.from_file(repository, type, path, parsed)
  rescue
    error in File.Error -> reraise error, __STACKTRACE__
  end

  defp artifact_path!(repository, type, id) do
    validate_type!(type)
    validate_id!(id)

    case @singletons[type] do
      {expected_id, relative_path} ->
        if id != expected_id do
          raise ArgumentError, "Artifact #{id} does not match #{type}."
        end

        {Path.join(repository["path"], relative_path), type}

      nil ->
        {_prefix, directory} = Map.fetch!(@collections, type)
        {Path.join([repository["path"], directory, "#{id}.md"]), type}
    end
    |> ensure_existing!()
  end

  defp ensure_existing!({path, type}) do
    unless File.exists?(path), do: raise(ArgumentError, "Artifact not found.")
    {path, type}
  end

  defp validate_type!(type) when is_binary(type) do
    unless type in artifact_types() do
      raise ArgumentError, "Unknown spec artifact type."
    end
  end

  defp validate_type!(_type), do: raise(ArgumentError, "Unknown spec artifact type.")

  defp validate_collection_type!(type) do
    validate_type!(type)

    unless Map.has_key?(@collections, type) do
      raise ArgumentError, "Spec artifact type cannot be created this way."
    end
  end

  defp validate_id!(id) when is_binary(id) do
    if id == "" or String.contains?(id, ["..", "/", "\\"]) or
         not Regex.match?(~r/^[A-Za-z0-9._-]+$/, id) do
      raise ArgumentError, "Unsafe spec artifact id."
    end
  end

  defp validate_id!(_id), do: raise(ArgumentError, "Unsafe spec artifact id.")

  defp merge_metadata!(frontmatter, type, id, patch) when is_map(patch) do
    patch =
      patch
      |> Enum.map(fn {key, value} -> {to_string(key), value} end)
      |> Map.new()

    if Map.has_key?(patch, "type") and patch["type"] != type do
      raise ArgumentError, "Spec artifact type cannot be changed."
    end

    if Map.has_key?(patch, "id") and patch["id"] != id do
      raise ArgumentError, "Spec artifact id cannot be changed."
    end

    status = Map.get(patch, "status", frontmatter["status"] || "draft")
    validate_status!(status)

    patch =
      patch
      |> Map.drop(["type", "id", "created_at"])
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Map.merge(frontmatter, patch)
    |> Map.put("type", type)
    |> Map.put("id", id)
  end

  defp merge_metadata!(_frontmatter, _type, _id, _patch) do
    raise ArgumentError, "Spec artifact metadata must be an object."
  end

  defp validate_status!(status) when status in @statuses, do: :ok
  defp validate_status!(_status), do: raise(ArgumentError, "Unknown spec artifact status.")

  defp ids_for_file(path) do
    frontmatter_id =
      path
      |> File.read!()
      |> Markdown.parse()
      |> Map.get(:frontmatter)
      |> Map.get("id")

    [Path.basename(path, ".md"), frontmatter_id]
    |> Enum.reject(&is_nil/1)
  end

  defp number_for_id(nil, _prefix), do: nil

  defp number_for_id(value, prefix) when is_binary(value) do
    case Regex.run(~r/^#{Regex.escape(prefix)}-(\d+)$/, value) do
      [_all, number] -> String.to_integer(number)
      _ -> nil
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
