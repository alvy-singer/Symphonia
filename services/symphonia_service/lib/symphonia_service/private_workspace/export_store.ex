defmodule SymphoniaService.PrivateWorkspace.ExportStore do
  @moduledoc """
  Private local metadata for manual workspace artifact exports.

  Export records live beside private workspace state and never inside the
  managed repository.
  """

  alias SymphoniaService.PrivateWorkspace

  @terminal_states ~w(merged closed unknown unlinked)

  def list(repository, opts \\ []) do
    repository
    |> read_store(opts)
    |> Map.get("exports", [])
    |> Enum.sort_by(&{&1["updated_at"] || &1["created_at"] || "", &1["id"]})
  end

  def list_for_artifact(repository, kind, artifact_id, opts \\ []) do
    repository
    |> list(opts)
    |> Enum.filter(&(&1["artifact_kind"] == kind and &1["artifact_id"] == artifact_id))
  end

  def latest_for_artifact(repository, kind, artifact_id, opts \\ []) do
    repository
    |> list_for_artifact(kind, artifact_id, opts)
    |> List.last()
  end

  def latest_for_target(repository, kind, artifact_id, target_path, opts \\ []) do
    repository
    |> list_for_artifact(kind, artifact_id, opts)
    |> Enum.filter(&(&1["target_path"] == target_path))
    |> List.last()
  end

  def get!(repository, export_id, opts \\ []) do
    repository
    |> list(opts)
    |> Enum.find(&(&1["id"] == export_id))
    |> case do
      nil -> raise ArgumentError, "Export record not found."
      export -> export
    end
  end

  def open_for_target?(repository, kind, artifact_id, target_path, opts \\ []) do
    repository
    |> list_for_artifact(kind, artifact_id, opts)
    |> Enum.any?(fn export ->
      export["target_path"] == target_path and export["status"] == "pr_open" and
        export["pull_request_state"] not in @terminal_states
    end)
  end

  def create(repository, attrs, opts \\ []) when is_map(attrs) do
    now = now()

    attrs
    |> normalize()
    |> Map.put_new("id", export_id())
    |> Map.put_new("provider", "github")
    |> Map.put_new("status", "never_exported")
    |> Map.put_new("created_at", now)
    |> Map.put("updated_at", now)
    |> upsert(repository, opts)
  end

  def update(repository, export_id, attrs, opts \\ []) when is_map(attrs) do
    export = get!(repository, export_id, opts)

    export
    |> Map.merge(normalize(attrs))
    |> Map.put("updated_at", now())
    |> upsert(repository, opts)
  end

  def unlink(repository, export_id, opts \\ []) do
    update(
      repository,
      export_id,
      %{
        "status" => "unlinked",
        "pull_request_state" => "unlinked"
      },
      opts
    )
  end

  def public(export) when is_map(export) do
    %{
      "id" => export["id"],
      "artifactId" => export["artifact_id"],
      "artifactKind" => export["artifact_kind"],
      "repoKey" => export["repo_key"],
      "provider" => export["provider"] || "github",
      "targetRepo" => export["target_repo"],
      "targetPath" => export["target_path"],
      "baseBranch" => export["base_branch"],
      "exportBranch" => export["export_branch"],
      "exportedRevisionId" => export["exported_revision_id"],
      "lastExportedAt" => export["last_exported_at"],
      "pullRequestUrl" => export["pull_request_url"],
      "pullRequestNumber" => export["pull_request_number"],
      "pullRequestState" => export["pull_request_state"],
      "status" => export["status"] || "never_exported",
      "createdAt" => export["created_at"],
      "updatedAt" => export["updated_at"]
    }
    |> reject_nil()
  end

  defp upsert(export, repository, opts) do
    store = read_store(repository, opts)

    exports =
      store
      |> Map.get("exports", [])
      |> Enum.reject(&(&1["id"] == export["id"]))
      |> Kernel.++([export])
      |> Enum.sort_by(&{&1["artifact_kind"], &1["artifact_id"], &1["updated_at"], &1["id"]})

    write_store!(repository, Map.put(store, "exports", exports), opts)
    export
  end

  defp read_store(repository, opts) do
    path = path(repository, opts)

    case File.read(path) do
      {:ok, body} when body != "" ->
        body
        |> JSON.decode!()
        |> Map.put_new("version", 1)
        |> Map.put_new("repoKey", repository["key"])
        |> Map.update("exports", [], &List.wrap/1)

      _ ->
        %{"version" => 1, "repoKey" => repository["key"], "exports" => []}
    end
  end

  defp write_store!(repository, store, opts) do
    path = path(repository, opts)
    path |> Path.dirname() |> File.mkdir_p!()
    temp_path = "#{path}.tmp-#{System.unique_integer([:positive])}"
    File.write!(temp_path, JSON.encode!(store))
    File.rename!(temp_path, path)
    chmod_private(path)
    path
  end

  defp path(repository, opts),
    do: Path.join(PrivateWorkspace.root(repository, opts), "exports.json")

  defp normalize(attrs) do
    attrs
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp export_id do
    "export_" <> Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp chmod_private(path) do
    File.chmod(path, 0o600)
    :ok
  rescue
    _error -> :ok
  end

  defp reject_nil(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
end
