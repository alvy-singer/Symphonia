defmodule SymphoniaService.PrivateWorkspace.ExportPreview do
  @moduledoc """
  Builds a no-write preview for manual GitHub artifact exports.
  """

  alias SymphoniaService.GitHub.{Auth, Client}
  alias SymphoniaService.PrivateWorkspace
  alias SymphoniaService.PrivateWorkspace.{ExportPolicy, ExportRenderer, ExportStore}

  def preview(repository, kind, id, attrs \\ %{}, opts \\ []) when is_map(attrs) do
    artifact = PrivateWorkspace.read_artifact(repository, kind, id, opts)
    ExportPolicy.validate_exportable!(kind)

    revision_id =
      string(attrs, "revisionId") || string(attrs, "revision_id") || artifact["latestRevisionId"]

    ExportPolicy.validate_revision!(artifact, revision_id)

    target_path =
      attrs
      |> target_path(artifact)
      |> ExportPolicy.normalize_target_path!()

    github_repo = ExportPolicy.github_repo!(repository)

    base_branch =
      string(attrs, "baseBranch") || string(attrs, "base_branch") || github_repo["default_branch"]

    token = Auth.token_for_repository(github_repo["owner"], github_repo["name"])
    markdown = ExportRenderer.render(repository, kind, id, revision_id, opts)
    export = ExportStore.latest_for_target(repository, kind, id, target_path, opts)
    target = github_contents(token, github_repo, target_path, base_branch)
    {operation, warnings} = operation(export, target)

    %{
      "artifactId" => id,
      "artifactKind" => kind,
      "revisionId" => revision_id,
      "targetRepo" => github_repo["target_repo"],
      "targetPath" => target_path,
      "baseBranch" => base_branch,
      "operation" => operation,
      "markdownPreview" => markdown,
      "changedSinceLastExport" => changed_since_last_export?(artifact, export),
      "warnings" => warnings,
      "targetSha" => target && target["sha"],
      "lastKnownGithubSha" => export && export["last_known_github_sha"]
    }
    |> reject_nil()
  end

  def default_target_path(artifact), do: ExportPolicy.default_target_path(artifact)

  defp target_path(attrs, artifact) do
    string(attrs, "targetPath") || string(attrs, "target_path") ||
      artifact["exportTargetPath"] || artifact["legacyRepoPath"] ||
      ExportPolicy.default_target_path(artifact)
  end

  defp operation(nil, nil), do: {"create", []}

  defp operation(nil, %{}), do: {"conflict", ["A file already exists at this path."]}

  defp operation(%{"status" => "unlinked"}, nil), do: {"create", []}

  defp operation(%{"status" => "unlinked"}, %{}),
    do: {"conflict", ["A file already exists at this path."]}

  defp operation(export, nil) do
    if present?(export["last_known_github_sha"]) do
      {"conflict", ["Linked GitHub file was not found."]}
    else
      {"create", []}
    end
  end

  defp operation(export, target) do
    cond do
      present?(export["last_known_github_sha"]) and
          export["last_known_github_sha"] != target["sha"] ->
        {"conflict", ["GitHub file changed since last export."]}

      true ->
        {"update", []}
    end
  end

  defp changed_since_last_export?(_artifact, nil), do: true

  defp changed_since_last_export?(artifact, export) do
    export["exported_revision_id"] != artifact["latestRevisionId"]
  end

  defp github_contents(token, github_repo, target_path, base_branch) do
    case client().get_contents(
           token,
           github_repo["owner"],
           github_repo["name"],
           target_path,
           base_branch
         ) do
      {:ok, content} ->
        content

      {:error, %{"status" => 404}} ->
        nil

      {:error, payload} ->
        raise ArgumentError, payload["message"] || "Could not read GitHub target file."
    end
  end

  defp client, do: Application.get_env(:symphonia_service, :github_client, Client)

  defp string(attrs, camel, snake \\ nil) do
    value = attrs[camel] || (snake && attrs[snake])

    case value do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: nil, else: value

      _ ->
        nil
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
  defp reject_nil(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
end
