defmodule SymphoniaService.PrivateWorkspace do
  @moduledoc """
  Service-readable private workspace state for repository knowledge artifacts.

  V1 keeps the store local to Symphonia beside the repository registry. The
  managed repository is only touched by explicit export flows.
  """

  alias SymphoniaService.Markdown
  alias SymphoniaService.PrivateWorkspace.{ExportStatus, ExportStore}
  alias SymphoniaService.Secrets.Redactor
  alias SymphoniaService.SpecWorkspace.Templates
  alias SymphoniaService.Validation.Evidence

  @statuses ~w(draft in_discussion requirements_ready plan_ready ready_for_approval approved created archived)
  @artifact_kinds ~w(codebase_map codebase_conventions milestone plan decision run_summary)

  @evidence_kinds ~w(
    validation_excerpt
    command_log_ref
    test_result
    screenshot_ref
    video_ref
    trace_ref
    diff_ref
    provider_transcript_ref
    review_finding
  )

  @export_statuses ~w(never_exported linked changed_since_export pr_open conflict unlinked)

  @singletons %{
    "codebase_map" => {"codebase-map", "Codebase map"},
    "codebase_conventions" => {"codebase-conventions", "Codebase conventions"}
  }

  @collections %{
    "milestone" => "milestone",
    "plan" => "plan",
    "decision" => "decision",
    "run_summary" => "run-summary"
  }

  @sections [
    {"Codebase", ["codebase_map", "codebase_conventions"]},
    {"Milestones", ["milestone"]},
    {"Plans", ["plan"]},
    {"Decisions", ["decision"]},
    {"Run summaries", ["run_summary"]}
  ]

  @legacy_singletons %{
    "codebase_map" => {"codebase-map", "symphonia/codebase/map.md"},
    "codebase_conventions" => {"codebase-conventions", "symphonia/codebase/conventions.md"}
  }

  @legacy_collections %{
    "milestone" => "symphonia/milestones",
    "plan" => "symphonia/plans",
    "decision" => "symphonia/decisions",
    "run_summary" => "symphonia/run-summaries"
  }

  def statuses, do: @statuses
  def artifact_kinds, do: @artifact_kinds
  def evidence_kinds, do: @evidence_kinds
  def export_statuses, do: @export_statuses

  def root(repository, opts \\ []) do
    registry_path = registry_path(repository, opts)
    Path.join([Path.dirname(registry_path), "workspace", safe_repo_key(repository["key"])])
  end

  def state(repository, opts \\ []) do
    index = read_index(repository, opts)
    artifact_keys = MapSet.new(Enum.map(index["artifacts"], &artifact_key/1))

    missing_defaults =
      @singletons
      |> Enum.reject(fn {kind, {id, _title}} ->
        MapSet.member?(artifact_keys, "#{kind}:#{id}")
      end)
      |> Enum.map(fn {kind, _config} -> kind end)
      |> Enum.sort()

    workspace_root = root(repository, opts)

    %{
      "exists" =>
        File.dir?(workspace_root) or index["artifacts"] != [] or index["evidence"] != [],
      "initialized" => File.exists?(index_path(repository, opts)) and missing_defaults == [],
      "path" => "private-workspace/#{repository["key"]}",
      "missingDirectories" => [],
      "missingDefaultArtifacts" => missing_defaults,
      "statuses" => @statuses,
      "artifactKinds" => @artifact_kinds,
      "evidenceKinds" => @evidence_kinds,
      "exportStatuses" => @export_statuses
    }
  end

  def initialize(repository, opts \\ []) do
    ensure_root!(repository, opts)

    Enum.each(@singletons, fn {kind, {id, title}} ->
      unless artifact_exists?(repository, kind, id, opts) do
        create_artifact(repository, kind, id, %{"title" => title}, opts)
      end
    end)

    state(repository, opts)
  end

  def sections(repository, opts \\ []) do
    artifacts = list_artifacts(repository, opts)

    Enum.map(@sections, fn {label, kinds} ->
      section_artifacts =
        kinds
        |> Enum.flat_map(&Map.get(artifacts, &1, []))
        |> Enum.map(&summary/1)

      %{"label" => label, "types" => kinds, "artifacts" => section_artifacts}
    end)
  end

  def list_artifacts(repository, opts \\ []) do
    @artifact_kinds
    |> Enum.map(fn kind -> {kind, list_artifacts(repository, kind, opts)} end)
    |> Map.new()
  end

  def list_artifacts(repository, kind, opts) when is_binary(kind) do
    validate_artifact_kind!(kind)

    repository
    |> read_index(opts)
    |> Map.get("artifacts", [])
    |> Enum.filter(&(&1["kind"] == kind))
    |> Enum.sort_by(&{&1["kind"], &1["id"]})
    |> Enum.map(&artifact_from_metadata(repository, &1, opts))
  end

  def read_artifact(repository, kind, id, opts \\ []) do
    validate_artifact_kind!(kind)
    validate_id!(id)

    repository
    |> read_index(opts)
    |> Map.get("artifacts", [])
    |> Enum.find(&(&1["kind"] == kind and &1["id"] == id))
    |> case do
      nil -> raise ArgumentError, "Artifact not found."
      metadata -> artifact_from_metadata(repository, metadata, opts)
    end
  end

  def read_revision(repository, kind, id, revision_id, opts \\ []) do
    validate_artifact_kind!(kind)
    validate_id!(id)
    validate_id!(revision_id)

    artifact = read_artifact(repository, kind, id, opts)
    revision_ids = artifact["metadata"]["revisions"] |> List.wrap() |> Enum.map(& &1["id"])

    unless revision_id in revision_ids do
      raise ArgumentError, "Private workspace revision not found."
    end

    read_revision_blob(repository, kind, id, revision_id, opts)
  end

  def create_artifact(repository, kind, attrs \\ %{}, opts \\ []) do
    validate_collection_kind!(kind)
    create_artifact(repository, kind, next_id(repository, kind, opts), attrs, opts)
  end

  def create_artifact(repository, kind, id, attrs, opts) when is_map(attrs) do
    validate_artifact_kind!(kind)
    validate_id!(id)
    validate_singleton_id!(kind, id)

    if artifact_exists?(repository, kind, id, opts),
      do: raise(ArgumentError, "Artifact already exists.")

    attrs = normalize_attrs(attrs)
    body = Map.get(attrs, "body") || default_body(kind, id, attrs)
    metadata = new_metadata(kind, id, attrs)
    write_artifact_with_revision(repository, metadata, body, opts)
  end

  def create_or_update_artifact(repository, kind, id, attrs, opts \\ []) when is_map(attrs) do
    if artifact_exists?(repository, kind, id, opts) do
      patch =
        %{"metadata" => Map.drop(normalize_attrs(attrs), ["body"])}
        |> maybe_put_body(attrs)

      update_artifact(repository, kind, id, patch, opts)
    else
      create_artifact(repository, kind, id, attrs, opts)
    end
  end

  def update_artifact(repository, kind, id, patch, opts \\ []) when is_map(patch) do
    artifact = read_artifact(repository, kind, id, opts)
    metadata_patch = normalize_metadata_patch(Map.get(patch, "metadata", %{}), kind, id)
    current_body = artifact["body"] || ""
    next_body = Map.get(patch, "body", current_body)

    unless is_binary(next_body), do: raise(ArgumentError, "Artifact body must be a string.")

    body_changed? = next_body != current_body
    now = now()

    metadata =
      artifact["metadata"]
      |> Map.merge(metadata_patch)
      |> Map.put("kind", kind)
      |> Map.put("id", id)
      |> Map.put("updated_at", now)
      |> Map.put("title", title_for(metadata_patch, artifact["title"], kind))
      |> Map.put(
        "status",
        Map.get(metadata_patch, "status", artifact["status"] || default_status(kind))
      )
      |> maybe_mark_changed_since_export(body_changed?)
      |> reject_nil()

    validate_status!(metadata["status"])
    update_artifact_metadata(repository, metadata, next_body, body_changed?, opts)
  end

  def artifact_exists?(repository, kind, id, opts \\ []) do
    validate_artifact_kind!(kind)
    validate_id!(id)

    repository
    |> read_index(opts)
    |> Map.get("artifacts", [])
    |> Enum.any?(&(&1["kind"] == kind and &1["id"] == id))
  end

  def next_id(repository, kind, opts \\ []) do
    validate_collection_kind!(kind)
    prefix = Map.fetch!(@collections, kind)

    used =
      repository
      |> read_index(opts)
      |> Map.get("artifacts", [])
      |> Enum.filter(&(&1["kind"] == kind))
      |> Enum.reduce(MapSet.new(), fn artifact, acc ->
        case number_for_id(artifact["id"], prefix) do
          nil -> acc
          number -> MapSet.put(acc, number)
        end
      end)

    number = used |> MapSet.to_list() |> Enum.max(fn -> 0 end) |> Kernel.+(1)
    "#{prefix}-#{String.pad_leading(Integer.to_string(number), 3, "0")}"
  end

  def list_evidence(repository, opts \\ []) do
    repository
    |> read_index(opts)
    |> Map.get("evidence", [])
    |> Enum.sort_by(&{&1["kind"], &1["id"]})
    |> Enum.map(&evidence_from_metadata(repository, &1, opts))
  end

  def read_evidence(repository, kind, id, opts \\ []) do
    validate_evidence_kind!(kind)
    validate_id!(id)

    repository
    |> read_index(opts)
    |> Map.get("evidence", [])
    |> Enum.find(&(&1["kind"] == kind and &1["id"] == id))
    |> case do
      nil -> raise ArgumentError, "Evidence not found."
      metadata -> evidence_from_metadata(repository, metadata, opts)
    end
  end

  def create_evidence(repository, kind, attrs, opts \\ []) when is_map(attrs) do
    validate_evidence_kind!(kind)
    attrs = normalize_attrs(attrs)
    id = Map.get(attrs, "id") || evidence_id(kind)
    validate_id!(id)

    payload =
      attrs
      |> Map.get("payload", Map.drop(attrs, ["id", "title", "status", "artifact_id", "run_id"]))
      |> sanitize_evidence_payload()

    metadata = new_evidence_metadata(kind, id, attrs)
    write_evidence(repository, metadata, payload, opts)
  end

  def record_validation_evidence(repository, run, public_evidence, opts \\ []) do
    public_evidence
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {item, index} ->
      create_evidence(
        repository,
        "validation_excerpt",
        %{
          "id" => "#{slug(run["id"] || "run")}-validation-#{index}",
          "title" => item["label"] || "Validation evidence",
          "status" => item["status"] || "not_run",
          "run_id" => run["id"],
          "payload" => item
        },
        opts
      )
    end)
  end

  def legacy_artifacts(repository, opts \\ []) do
    imported =
      repository
      |> read_index(opts)
      |> Map.get("artifacts", [])
      |> Enum.reduce(%{}, fn artifact, acc ->
        case artifact["legacyRepoPath"] || artifact["legacy_repo_path"] do
          path when is_binary(path) -> Map.put(acc, path, artifact)
          _ -> acc
        end
      end)

    singleton_legacy(repository, imported) ++ collection_legacy(repository, imported)
  end

  def import_legacy(repository, payload \\ %{}, opts \\ []) do
    items = selected_legacy_items(repository, payload, opts)

    imported =
      Enum.map(items, fn item ->
        attrs =
          item["metadata"]
          |> Map.merge(%{
            "title" => item["title"],
            "status" => item["status"],
            "body" => item["body"],
            "legacy_repo_path" => item["legacyRepoPath"],
            "export_status" => "linked"
          })

        create_or_update_artifact(repository, item["kind"], item["id"], attrs, opts)
      end)

    %{"imported" => imported, "count" => length(imported)}
  end

  def export_artifact(repository, kind, id, attrs \\ %{}, opts \\ []) do
    artifact = read_artifact(repository, kind, id, opts)
    attrs = normalize_attrs(attrs)
    selected_revision = Map.get(attrs, "revision_id") || artifact["latestRevisionId"]
    branch = Map.get(attrs, "review_branch") || export_branch(kind, id, selected_revision)
    pr_url = Map.get(attrs, "github_pr_url") || Map.get(attrs, "githubPrUrl")
    status = if is_binary(pr_url) and String.trim(pr_url) != "", do: "pr_open", else: "linked"

    update_artifact(
      repository,
      kind,
      id,
      %{
        "metadata" => %{
          "export_status" => status,
          "exported_revision_id" => selected_revision,
          "review_branch" => branch,
          "github_pr_url" => pr_url
        }
      },
      opts
    )
  end

  def summary(artifact), do: Map.drop(artifact, ["body"])

  defp write_artifact_with_revision(repository, metadata, body, opts) do
    revision_id = revision_id()
    now = now()

    metadata =
      metadata
      |> Map.put("latest_revision_id", revision_id)
      |> Map.put("revisions", [%{"id" => revision_id, "created_at" => now}])

    write_revision_blob!(repository, metadata["kind"], metadata["id"], revision_id, body, opts)

    index = read_index(repository, opts)
    index = put_artifact(index, metadata)
    write_index!(repository, index, opts)
    read_artifact(repository, metadata["kind"], metadata["id"], opts)
  end

  defp update_artifact_metadata(repository, metadata, body, true, opts) do
    revision_id = revision_id()
    write_revision_blob!(repository, metadata["kind"], metadata["id"], revision_id, body, opts)

    metadata =
      metadata
      |> Map.put("latest_revision_id", revision_id)
      |> Map.update("revisions", [%{"id" => revision_id, "created_at" => now()}], fn revisions ->
        List.wrap(revisions) ++ [%{"id" => revision_id, "created_at" => now()}]
      end)

    index = read_index(repository, opts)
    write_index!(repository, put_artifact(index, metadata), opts)
    read_artifact(repository, metadata["kind"], metadata["id"], opts)
  end

  defp update_artifact_metadata(repository, metadata, _body, false, opts) do
    index = read_index(repository, opts)
    write_index!(repository, put_artifact(index, metadata), opts)
    read_artifact(repository, metadata["kind"], metadata["id"], opts)
  end

  defp write_evidence(repository, metadata, payload, opts) do
    write_evidence_blob!(repository, metadata["kind"], metadata["id"], payload, opts)
    index = read_index(repository, opts)
    write_index!(repository, put_evidence(index, metadata), opts)
    evidence_from_metadata(repository, metadata, opts)
  end

  defp artifact_from_metadata(repository, metadata, opts) do
    body =
      read_revision_blob(
        repository,
        metadata["kind"],
        metadata["id"],
        metadata["latest_revision_id"],
        opts
      )

    exports = ExportStore.list_for_artifact(repository, metadata["kind"], metadata["id"], opts)

    latest_export =
      ExportStore.latest_for_artifact(repository, metadata["kind"], metadata["id"], opts)

    artifact =
      %{
        "type" => metadata["kind"],
        "kind" => metadata["kind"],
        "id" => metadata["id"],
        "title" => metadata["title"],
        "status" => metadata["status"],
        "source" => metadata["source"],
        "createdAt" => metadata["created_at"],
        "updatedAt" => metadata["updated_at"],
        "path" => "private-workspace/#{metadata["kind"]}/#{metadata["id"]}",
        "latestRevisionId" => metadata["latest_revision_id"],
        "legacyRepoPath" => metadata["legacy_repo_path"],
        "reviewBranch" => metadata["review_branch"],
        "githubPrUrl" => metadata["github_pr_url"],
        "metadata" => public_metadata(metadata),
        "body" => body
      }
      |> put_export_projection(metadata, latest_export, exports)
      |> reject_nil()

    artifact
  end

  defp put_export_projection(artifact, metadata, nil, exports) do
    Map.put(
      artifact,
      "exportStatus",
      ExportStatus.derive(artifact, exports, metadata["export_status"])
    )
  end

  defp put_export_projection(artifact, metadata, export, exports) do
    artifact
    |> Map.put("exportStatus", ExportStatus.derive(artifact, exports, metadata["export_status"]))
    |> Map.put("exportId", export["id"])
    |> Map.put("exportTargetPath", export["target_path"])
    |> Map.put("targetPath", export["target_path"])
    |> Map.put("targetRepo", export["target_repo"])
    |> Map.put("baseBranch", export["base_branch"])
    |> Map.put("reviewBranch", export["export_branch"] || metadata["review_branch"])
    |> Map.put("exportBranch", export["export_branch"])
    |> Map.put("exportedRevisionId", export["exported_revision_id"])
    |> Map.put("lastExportedAt", export["last_exported_at"])
    |> Map.put("githubPrUrl", export["pull_request_url"] || metadata["github_pr_url"])
    |> Map.put("pullRequestUrl", export["pull_request_url"])
    |> Map.put("pullRequestNumber", export["pull_request_number"])
    |> Map.put("pullRequestState", export["pull_request_state"])
  end

  defp evidence_from_metadata(repository, metadata, opts) do
    payload = read_evidence_blob(repository, metadata["kind"], metadata["id"], opts)

    %{
      "kind" => metadata["kind"],
      "id" => metadata["id"],
      "title" => metadata["title"],
      "status" => metadata["status"],
      "artifactId" => metadata["artifact_id"],
      "runId" => metadata["run_id"],
      "createdAt" => metadata["created_at"],
      "updatedAt" => metadata["updated_at"],
      "payload" => payload
    }
    |> reject_nil()
  end

  defp public_metadata(metadata) do
    metadata
    |> Map.drop(["kind"])
    |> Map.put("type", metadata["kind"])
    |> Map.put("id", metadata["id"])
    |> Map.put("latest_revision_id", metadata["latest_revision_id"])
  end

  defp new_metadata(kind, id, attrs) do
    attrs = normalize_attrs(attrs)
    status = Map.get(attrs, "status") || default_status(kind)
    validate_status!(status)
    now = now()

    attrs
    |> Map.drop([
      "body",
      "type",
      "kind",
      "id",
      "created_at",
      "updated_at",
      "latest_revision_id",
      "revisions"
    ])
    |> Map.put("kind", kind)
    |> Map.put("id", id)
    |> Map.put("title", title_for(attrs, nil, kind))
    |> Map.put("status", status)
    |> Map.put("created_at", now)
    |> Map.put("updated_at", now)
    |> Map.put("source", Map.get(attrs, "source") || "clarise")
    |> Map.put("export_status", Map.get(attrs, "export_status") || "never_exported")
    |> reject_nil()
  end

  defp new_evidence_metadata(kind, id, attrs) do
    now = now()

    %{
      "kind" => kind,
      "id" => id,
      "title" => string_attr(attrs, "title") || evidence_title(kind),
      "status" => string_attr(attrs, "status"),
      "artifact_id" => string_attr(attrs, "artifact_id"),
      "run_id" => string_attr(attrs, "run_id"),
      "created_at" => now,
      "updated_at" => now
    }
    |> reject_nil()
  end

  defp normalize_metadata_patch(patch, kind, id) when is_map(patch) do
    patch = normalize_attrs(patch)

    if Map.has_key?(patch, "type") and patch["type"] != kind do
      raise ArgumentError, "Spec artifact type cannot be changed."
    end

    if Map.has_key?(patch, "kind") and patch["kind"] != kind do
      raise ArgumentError, "Spec artifact type cannot be changed."
    end

    if Map.has_key?(patch, "id") and patch["id"] != id do
      raise ArgumentError, "Spec artifact id cannot be changed."
    end

    patch
    |> Map.drop(["type", "kind", "id", "created_at", "latest_revision_id", "revisions"])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_metadata_patch(_patch, _kind, _id),
    do: raise(ArgumentError, "Spec artifact metadata must be an object.")

  defp maybe_mark_changed_since_export(metadata, false), do: metadata

  defp maybe_mark_changed_since_export(%{"export_status" => status} = metadata, true)
       when status in ["linked", "pr_open"] do
    Map.put(metadata, "export_status", "changed_since_export")
  end

  defp maybe_mark_changed_since_export(metadata, _body_changed?), do: metadata

  defp selected_legacy_items(repository, payload, opts) do
    legacy = legacy_artifacts(repository, opts)
    payload = normalize_attrs(payload || %{})

    selectors =
      cond do
        is_list(payload["items"]) -> payload["items"]
        payload["all"] == true -> :all
        payload["kind"] && payload["id"] -> [payload]
        true -> :all
      end

    case selectors do
      :all ->
        legacy

      values ->
        Enum.flat_map(values, fn selector ->
          selector = normalize_attrs(selector)

          Enum.filter(legacy, fn item ->
            matches_selector?(item, selector)
          end)
        end)
    end
    |> Enum.uniq_by(&{&1["kind"], &1["id"], &1["legacyRepoPath"]})
  end

  defp matches_selector?(item, selector) do
    kind_ok? = blank?(selector["kind"]) or selector["kind"] == item["kind"]
    id_ok? = blank?(selector["id"]) or selector["id"] == item["id"]
    path_ok? = blank?(selector["path"]) or selector["path"] == item["legacyRepoPath"]
    kind_ok? and id_ok? and path_ok?
  end

  defp singleton_legacy(repository, imported) do
    Enum.flat_map(@legacy_singletons, fn {kind, {id, path}} ->
      read_legacy_path(repository, kind, id, path, imported)
    end)
  end

  defp collection_legacy(repository, imported) do
    Enum.flat_map(@legacy_collections, fn {kind, directory} ->
      repository["path"]
      |> Path.join(directory)
      |> Path.join("*.md")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(fn path ->
        id = Path.basename(path, ".md")
        relative = Path.relative_to(path, repository["path"])
        read_legacy_path(repository, kind, id, relative, imported)
      end)
    end)
  end

  defp read_legacy_path(repository, kind, fallback_id, relative_path, imported) do
    full_path = Path.join(repository["path"], relative_path)

    if File.exists?(full_path) do
      parsed = full_path |> File.read!() |> Markdown.parse()
      id = parsed.frontmatter["id"] || fallback_id
      title = parsed.frontmatter["title"] || title_from_body(parsed.body) || id
      status = parsed.frontmatter["status"] || default_status(kind)
      private = imported[relative_path]

      [
        %{
          "kind" => kind,
          "type" => kind,
          "id" => id,
          "title" => title,
          "status" => status,
          "legacyRepoPath" => relative_path,
          "imported" => not is_nil(private),
          "privateArtifactId" => private && private["id"],
          "exportStatus" => private && private["export_status"],
          "metadata" => normalize_attrs(parsed.frontmatter),
          "body" => parsed.body
        }
        |> reject_nil()
      ]
    else
      []
    end
  end

  defp put_artifact(index, metadata) do
    artifacts =
      index
      |> Map.get("artifacts", [])
      |> Enum.reject(&(&1["kind"] == metadata["kind"] and &1["id"] == metadata["id"]))

    Map.put(index, "artifacts", Enum.sort_by(artifacts ++ [metadata], &{&1["kind"], &1["id"]}))
  end

  defp put_evidence(index, metadata) do
    evidence =
      index
      |> Map.get("evidence", [])
      |> Enum.reject(&(&1["kind"] == metadata["kind"] and &1["id"] == metadata["id"]))

    Map.put(index, "evidence", Enum.sort_by(evidence ++ [metadata], &{&1["kind"], &1["id"]}))
  end

  defp read_index(repository, opts) do
    path = index_path(repository, opts)

    case File.read(path) do
      {:ok, body} when body != "" ->
        body
        |> JSON.decode!()
        |> Map.put_new("version", 1)
        |> Map.put_new("repoKey", repository["key"])
        |> Map.update("artifacts", [], &List.wrap/1)
        |> Map.update("evidence", [], &List.wrap/1)

      _ ->
        %{"version" => 1, "repoKey" => repository["key"], "artifacts" => [], "evidence" => []}
    end
  end

  defp write_index!(repository, index, opts) do
    path = index_path(repository, opts)
    path |> Path.dirname() |> File.mkdir_p!()
    temp_path = "#{path}.tmp-#{System.unique_integer([:positive])}"
    File.write!(temp_path, JSON.encode!(index))
    File.rename!(temp_path, path)
    chmod_private(path)
    path
  end

  defp index_path(repository, opts), do: Path.join(root(repository, opts), "index.json")

  defp ensure_root!(repository, opts) do
    workspace_root = root(repository, opts)
    File.mkdir_p!(workspace_root)
    File.chmod(workspace_root, 0o700)
    workspace_root
  rescue
    _error -> root(repository, opts)
  end

  defp write_revision_blob!(repository, kind, id, revision_id, body, opts) do
    path = revision_path(repository, kind, id, revision_id, opts)
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, body)
    chmod_private(path)
    path
  end

  defp read_revision_blob(_repository, _kind, _id, nil, _opts), do: ""

  defp read_revision_blob(repository, kind, id, revision_id, opts) do
    case File.read(revision_path(repository, kind, id, revision_id, opts)) do
      {:ok, body} ->
        body

      {:error, :enoent} ->
        ""

      {:error, reason} ->
        raise File.Error,
          reason: reason,
          action: "read file",
          path: revision_path(repository, kind, id, revision_id, opts)
    end
  end

  defp write_evidence_blob!(repository, kind, id, payload, opts) do
    path = evidence_path(repository, kind, id, opts)
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, JSON.encode!(payload))
    chmod_private(path)
    path
  end

  defp read_evidence_blob(repository, kind, id, opts) do
    case File.read(evidence_path(repository, kind, id, opts)) do
      {:ok, body} ->
        JSON.decode!(body)

      {:error, :enoent} ->
        %{}

      {:error, reason} ->
        raise File.Error,
          reason: reason,
          action: "read file",
          path: evidence_path(repository, kind, id, opts)
    end
  end

  defp revision_path(repository, kind, id, revision_id, opts) do
    Path.join([root(repository, opts), "blobs", "artifacts", kind, id, "#{revision_id}.md"])
  end

  defp evidence_path(repository, kind, id, opts) do
    Path.join([root(repository, opts), "blobs", "evidence", kind, "#{id}.json"])
  end

  defp registry_path(repository, opts) do
    Keyword.get(opts, :registry_path) ||
      repository["_registry_path"] ||
      repository["registry_path"] ||
      SymphoniaService.default_registry_path()
  end

  defp artifact_key(%{"kind" => kind, "id" => id}), do: "#{kind}:#{id}"
  defp artifact_key(_artifact), do: ""

  defp validate_artifact_kind!(kind) when kind in @artifact_kinds, do: :ok

  defp validate_artifact_kind!(_kind),
    do: raise(ArgumentError, "Unknown private workspace artifact kind.")

  defp validate_evidence_kind!(kind) when kind in @evidence_kinds, do: :ok

  defp validate_evidence_kind!(_kind),
    do: raise(ArgumentError, "Unknown private workspace evidence kind.")

  defp validate_collection_kind!(kind) do
    validate_artifact_kind!(kind)

    unless Map.has_key?(@collections, kind) do
      raise ArgumentError, "Private workspace artifact kind cannot be created this way."
    end
  end

  defp validate_singleton_id!(kind, id) do
    case @singletons[kind] do
      {^id, _title} -> :ok
      {expected, _title} -> raise ArgumentError, "Artifact #{id} does not match #{expected}."
      nil -> :ok
    end
  end

  defp validate_id!(id) when is_binary(id) do
    if id == "" or String.contains?(id, ["..", "/", "\\"]) or
         not Regex.match?(~r/^[A-Za-z0-9._-]+$/, id) do
      raise ArgumentError, "Unsafe private workspace id."
    end
  end

  defp validate_id!(_id), do: raise(ArgumentError, "Unsafe private workspace id.")

  defp validate_status!(status) when status in @statuses, do: :ok
  defp validate_status!(_status), do: raise(ArgumentError, "Unknown spec artifact status.")

  defp default_status("run_summary"), do: "created"
  defp default_status(_kind), do: "draft"

  defp default_body("run_summary", id, attrs) do
    title = string_attr(attrs, "title") || "Run summary"
    "# #{title}\n\nRun summary: #{id}\n"
  end

  defp default_body(kind, id, attrs), do: Templates.body(kind, id, attrs)

  defp title_for(attrs, current, kind) do
    string_attr(attrs, "title") || current || default_title(kind)
  end

  defp default_title("run_summary"), do: "Run summary"
  defp default_title(kind), do: Templates.title(kind)

  defp evidence_title("validation_excerpt"), do: "Validation excerpt"
  defp evidence_title(kind), do: String.replace(kind, "_", " ")

  defp normalize_attrs(attrs) when is_map(attrs) do
    attrs
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp normalize_attrs(_attrs), do: %{}

  defp maybe_put_body(patch, attrs) do
    attrs = normalize_attrs(attrs)
    if Map.has_key?(attrs, "body"), do: Map.put(patch, "body", attrs["body"]), else: patch
  end

  defp string_attr(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: nil, else: value

      _ ->
        nil
    end
  end

  defp sanitize_evidence_payload(payload) when is_map(payload) do
    payload
    |> Enum.map(fn {key, value} -> {to_string(key), sanitize_evidence_payload(value)} end)
    |> Map.new()
  end

  defp sanitize_evidence_payload(payload) when is_list(payload) do
    Enum.map(payload, &sanitize_evidence_payload/1)
  end

  defp sanitize_evidence_payload(payload) when is_binary(payload) do
    case Redactor.sanitize_value(payload) do
      :drop -> nil
      value -> Evidence.sanitize_public_text(value)
    end
  end

  defp sanitize_evidence_payload(payload) when is_integer(payload) or is_boolean(payload),
    do: payload

  defp sanitize_evidence_payload(_payload), do: nil

  defp number_for_id(value, prefix) when is_binary(value) do
    case Regex.run(~r/^#{Regex.escape(prefix)}-(\d+)$/, value) do
      [_all, number] -> String.to_integer(number)
      _ -> nil
    end
  end

  defp number_for_id(_value, _prefix), do: nil

  defp title_from_body(body) do
    body
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case Regex.run(~r/^#\s+(.+)$/, String.trim(line)) do
        [_all, title] -> title
        _ -> nil
      end
    end)
  end

  defp export_branch(kind, id, revision_id) do
    "symphonia/private-workspace/#{slug(kind)}/#{slug(id)}-#{slug(revision_id || "latest")}"
  end

  defp evidence_id(kind), do: "#{slug(kind)}-#{System.unique_integer([:positive])}"

  defp revision_id do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    "rev-#{timestamp}-#{System.unique_integer([:positive])}"
  end

  defp safe_repo_key(key), do: slug(key || "repository")

  defp slug(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9._-]/, "-")
    |> String.trim("-")
    |> case do
      "" -> "item"
      slug -> slug
    end
  end

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")

  defp reject_nil(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp chmod_private(path) do
    File.chmod(path, 0o600)
    :ok
  rescue
    _error -> :ok
  end
end
