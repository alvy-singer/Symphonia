defmodule SymphoniaService.PrivateWorkspace.GitHubExporter do
  @moduledoc """
  Creates GitHub branches, writes exported snapshots, and opens export PRs.
  """

  alias SymphoniaService.GitHub.{Auth, Client}
  alias SymphoniaService.PrivateWorkspace
  alias SymphoniaService.PrivateWorkspace.{ExportPreview, ExportStore}

  def open_pr(repository, kind, id, attrs \\ %{}, opts \\ []) when is_map(attrs) do
    preview = ExportPreview.preview(repository, kind, id, attrs, opts)

    if preview["operation"] == "conflict" do
      raise ArgumentError,
            Enum.join(preview["warnings"] || ["Export target is in conflict."], " ")
    end

    if ExportStore.open_for_target?(repository, kind, id, preview["targetPath"], opts) do
      raise ArgumentError, "An export pull request is already open for this artifact path."
    end

    artifact = PrivateWorkspace.read_artifact(repository, kind, id, opts)
    github_repo = github_repo(preview)
    token = Auth.token_for_repository(github_repo["owner"], github_repo["name"])
    export_branch = create_export_branch(token, github_repo, preview["baseBranch"], artifact)

    file =
      write_file(
        token,
        github_repo,
        preview["targetPath"],
        export_branch,
        preview["markdownPreview"],
        preview["targetSha"],
        artifact
      )

    pr =
      open_pull_request(
        token,
        github_repo,
        export_branch,
        preview["baseBranch"],
        artifact,
        attrs,
        preview
      )

    now = now()

    export =
      ExportStore.create(
        repository,
        %{
          "artifact_id" => id,
          "artifact_kind" => kind,
          "repo_key" => repository["key"],
          "provider" => "github",
          "target_repo" => preview["targetRepo"],
          "target_path" => preview["targetPath"],
          "base_branch" => preview["baseBranch"],
          "export_branch" => export_branch,
          "exported_revision_id" => preview["revisionId"],
          "exported_content_hash" => content_hash(preview["markdownPreview"]),
          "last_known_github_sha" => preview["targetSha"],
          "pull_request_url" => pr["html_url"],
          "pull_request_number" => pr["number"],
          "pull_request_state" => pr["state"] || "open",
          "status" => "pr_open",
          "last_exported_at" => now,
          "github_file_sha" => file["sha"] || get_in(file, ["content", "sha"])
        },
        opts
      )

    artifact =
      PrivateWorkspace.update_artifact(
        repository,
        kind,
        id,
        %{
          "metadata" => %{
            "export_status" => "pr_open",
            "exported_revision_id" => preview["revisionId"],
            "review_branch" => export_branch,
            "github_pr_url" => pr["html_url"],
            "export_target_path" => preview["targetPath"],
            "github_pr_number" => pr["number"],
            "github_pr_state" => pr["state"] || "open",
            "last_exported_at" => now
          }
        },
        opts
      )

    %{"artifact" => artifact, "export" => ExportStore.public(export)}
  end

  def refresh(repository, kind, id, export_id, opts \\ []) do
    export = ExportStore.get!(repository, export_id, opts)
    artifact = PrivateWorkspace.read_artifact(repository, kind, id, opts)
    github_repo = github_repo(export["target_repo"])
    token = Auth.token_for_repository(github_repo["owner"], github_repo["name"])

    fresh_pr =
      case client().get_pull_request(
             token,
             github_repo["owner"],
             github_repo["name"],
             export["pull_request_number"]
           ) do
        {:ok, pr} ->
          pr

        {:error, payload} ->
          raise ArgumentError, payload["message"] || "Could not refresh export pull request."
      end

    merged? = fresh_pr["merged"] == true
    pr_state = if merged?, do: "merged", else: fresh_pr["state"] || "unknown"

    {status, github_sha} =
      refreshed_status(repository, artifact, export, pr_state, token, github_repo)

    export =
      ExportStore.update(
        repository,
        export_id,
        %{
          "pull_request_state" => pr_state,
          "pull_request_url" => fresh_pr["html_url"] || export["pull_request_url"],
          "status" => status,
          "last_known_github_sha" => github_sha || export["last_known_github_sha"]
        },
        opts
      )

    artifact =
      PrivateWorkspace.update_artifact(
        repository,
        kind,
        id,
        %{
          "metadata" => %{
            "export_status" => status,
            "github_pr_state" => pr_state,
            "github_pr_url" => export["pull_request_url"],
            "review_branch" => export["export_branch"]
          }
        },
        opts
      )

    %{"artifact" => artifact, "export" => ExportStore.public(export)}
  end

  def unlink(repository, kind, id, export_id, opts \\ []) do
    export = ExportStore.unlink(repository, export_id, opts)

    artifact =
      PrivateWorkspace.update_artifact(
        repository,
        kind,
        id,
        %{"metadata" => %{"export_status" => "unlinked"}},
        opts
      )

    %{"artifact" => artifact, "export" => ExportStore.public(export)}
  end

  defp refreshed_status(_repository, artifact, export, "merged", token, github_repo) do
    github_sha = target_sha(token, github_repo, export["target_path"], export["base_branch"])

    status =
      if artifact["latestRevisionId"] == export["exported_revision_id"] do
        "linked"
      else
        "changed_since_export"
      end

    {status, github_sha}
  end

  defp refreshed_status(_repository, _artifact, export, "open", _token, _github_repo) do
    {export["status"] || "pr_open", export["last_known_github_sha"]}
  end

  defp refreshed_status(_repository, artifact, export, "closed", token, github_repo) do
    github_sha = target_sha(token, github_repo, export["target_path"], export["base_branch"])

    status =
      cond do
        is_nil(github_sha) ->
          "conflict"

        present?(export["last_known_github_sha"]) and
            github_sha == export["last_known_github_sha"] ->
          if artifact["latestRevisionId"] == export["exported_revision_id"],
            do: "linked",
            else: "changed_since_export"

        true ->
          "conflict"
      end

    {status, github_sha}
  end

  defp refreshed_status(_repository, _artifact, export, _state, _token, _github_repo) do
    {"conflict", export["last_known_github_sha"]}
  end

  defp target_sha(token, github_repo, target_path, base_branch) do
    case client().get_contents(
           token,
           github_repo["owner"],
           github_repo["name"],
           target_path,
           base_branch
         ) do
      {:ok, content} -> content["sha"]
      {:error, %{"status" => 404}} -> nil
      {:error, _payload} -> nil
    end
  end

  defp create_export_branch(token, github_repo, base_branch, artifact) do
    base_sha =
      case client().get_branch(token, github_repo["owner"], github_repo["name"], base_branch) do
        {:ok, branch} ->
          get_in(branch, ["commit", "sha"]) || branch["sha"]

        {:error, payload} ->
          raise ArgumentError, payload["message"] || "GitHub base branch was not found."
      end

    branch_base =
      "symphonia/export/#{artifact["type"]}/#{slug(artifact["title"] || artifact["id"])}"

    0..5
    |> Enum.reduce_while(nil, fn attempt, _acc ->
      branch = if attempt == 0, do: branch_base, else: "#{branch_base}-#{attempt + 1}"

      case client().create_git_ref(token, github_repo["owner"], github_repo["name"], %{
             "ref" => "refs/heads/#{branch}",
             "sha" => base_sha
           }) do
        {:ok, _ref} ->
          {:halt, branch}

        {:error, %{"status" => 422}} ->
          {:cont, nil}

        {:error, payload} ->
          raise ArgumentError, payload["message"] || "Could not create export branch."
      end
    end)
    |> case do
      nil -> raise ArgumentError, "Could not create a collision-free export branch."
      branch -> branch
    end
  end

  defp write_file(token, github_repo, target_path, branch, markdown, target_sha, artifact) do
    payload =
      %{
        "message" => "Export #{artifact["type"]}: #{artifact["title"] || artifact["id"]}",
        "content" => Base.encode64(markdown),
        "branch" => branch
      }
      |> maybe_put("sha", target_sha)

    case client().put_contents(
           token,
           github_repo["owner"],
           github_repo["name"],
           target_path,
           payload
         ) do
      {:ok, file} ->
        file

      {:error, payload} ->
        raise ArgumentError, payload["message"] || "Could not write GitHub export file."
    end
  end

  defp open_pull_request(token, github_repo, export_branch, base_branch, artifact, attrs, preview) do
    payload = %{
      "title" =>
        string(attrs, "title") ||
          "Export #{artifact["type"]}: #{artifact["title"] || artifact["id"]}",
      "body" => string(attrs, "body") || default_pr_body(artifact, preview),
      "head" => export_branch,
      "base" => base_branch
    }

    case client().create_pull_request(token, github_repo["owner"], github_repo["name"], payload) do
      {:ok, pr} ->
        pr

      {:error, payload} ->
        raise ArgumentError, payload["message"] || "Could not open export pull request."
    end
  end

  defp default_pr_body(artifact, preview) do
    """
    ## Summary
    Exports a selected Symphonia private workspace artifact snapshot to the repository.

    ## Export details
    - Artifact type: #{artifact["type"]}
    - Target path: #{preview["targetPath"]}
    - Export mode: manual PR
    - Sync behavior: no live sync

    This PR publishes only the selected artifact revision. Future private edits will not update GitHub unless another export PR is opened.

    No private evidence, run logs, or provider transcripts.
    """
  end

  defp github_repo(%{"targetRepo" => target_repo}), do: github_repo(target_repo)
  defp github_repo(%{"target_repo" => target_repo}), do: github_repo(target_repo)

  defp github_repo(target_repo) when is_binary(target_repo) do
    case String.split(target_repo, "/", parts: 2) do
      [owner, name] -> %{"owner" => owner, "name" => name}
      _ -> raise ArgumentError, "GitHub repository link is invalid."
    end
  end

  defp content_hash(content),
    do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, content), case: :lower)

  defp slug(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "artifact"
      slug -> slug
    end
  end

  defp string(attrs, key) do
    case attrs[key] || attrs[camel_to_snake(key)] do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: nil, else: value

      _ ->
        nil
    end
  end

  defp camel_to_snake("baseBranch"), do: "base_branch"
  defp camel_to_snake("targetPath"), do: "target_path"
  defp camel_to_snake(key), do: key

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
  defp present?(value), do: is_binary(value) and String.trim(value) != ""
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  defp client, do: Application.get_env(:symphonia_service, :github_client, Client)
end
