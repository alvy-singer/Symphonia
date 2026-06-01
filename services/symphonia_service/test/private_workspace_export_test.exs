defmodule SymphoniaService.PrivateWorkspaceExportTest do
  use ExUnit.Case

  alias SymphoniaService.GitHub.InstallationStore
  alias SymphoniaService.PrivateWorkspace

  alias SymphoniaService.PrivateWorkspace.{
    ExportPreview,
    ExportRenderer,
    ExportStore,
    GitHubExporter
  }

  alias SymphoniaService.RepositoryRegistry

  defmodule StubClient do
    def create_installation_token(_jwt, _installation_id) do
      {:ok,
       %{
         "token" => "installation-token",
         "expires_at" =>
           DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
       }}
    end

    def get_contents("installation-token", "agora-creations", "symphonia", _path, "main") do
      case Application.get_env(:symphonia_service, :github_export_target, :missing) do
        :exists -> {:ok, %{"sha" => "base-file-sha"}}
        :changed -> {:ok, %{"sha" => "changed-file-sha"}}
        :missing -> {:error, %{"status" => 404, "message" => "Not found"}}
      end
    end

    def get_branch("installation-token", "agora-creations", "symphonia", "main") do
      {:ok, %{"name" => "main", "commit" => %{"sha" => "base-commit-sha"}}}
    end

    def create_git_ref("installation-token", "agora-creations", "symphonia", payload) do
      assert payload["ref"] =~ "refs/heads/symphonia/export/decision/"
      assert payload["sha"] == "base-commit-sha"
      {:ok, %{"ref" => payload["ref"]}}
    end

    def put_contents("installation-token", "agora-creations", "symphonia", path, payload) do
      assert path == "docs/symphonia/decisions/private-workspace-model.md"
      assert payload["branch"] =~ "symphonia/export/decision/"
      refute payload["branch"] == "main"

      markdown = Base.decode64!(payload["content"])
      assert markdown =~ "artifact_kind: decision"
      assert markdown =~ "Private Workspace Model"
      refute markdown =~ "SECRET_TOKEN=value"
      refute markdown =~ "/Users/local"
      refute markdown =~ "provider output"
      refute markdown =~ "thread_id"

      {:ok, %{"content" => %{"sha" => "branch-file-sha"}}}
    end

    def create_pull_request("installation-token", "agora-creations", "symphonia", payload) do
      assert payload["head"] =~ "symphonia/export/decision/"
      assert payload["base"] == "main"

      {:ok,
       %{
         "number" => 123,
         "html_url" => "https://github.com/agora-creations/symphonia/pull/123",
         "state" => "open",
         "head" => %{"ref" => payload["head"]},
         "base" => %{"ref" => "main"}
       }}
    end

    def get_pull_request("installation-token", "agora-creations", "symphonia", 123) do
      state = Application.get_env(:symphonia_service, :github_export_pr_state, :merged)

      {:ok,
       %{
         "number" => 123,
         "html_url" => "https://github.com/agora-creations/symphonia/pull/123",
         "state" => if(state == :open, do: "open", else: "closed"),
         "merged" => state == :merged,
         "head" => %{"ref" => "symphonia/export/decision/private-workspace-model"},
         "base" => %{"ref" => "main"}
       }}
    end
  end

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphonia-private-export-test-#{System.unique_integer([:positive])}"
      )

    repo_path = Path.join(root, "repo")
    registry_path = Path.join(root, "registry.json")
    github_home = Path.join(root, "github")
    private_key_path = Path.join(root, "github-app.pem")
    File.mkdir_p!(Path.join(repo_path, ".git"))
    write_private_key!(private_key_path)

    previous_app_id = System.get_env("SYMPHONIA_GITHUB_APP_ID")
    previous_private_key = System.get_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH")
    System.put_env("SYMPHONIA_GITHUB_APP_ID", "42")
    System.put_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH", private_key_path)

    Application.put_env(:symphonia_service, :github_client, StubClient)
    Application.put_env(:symphonia_service, :github_home, github_home)
    Application.put_env(:symphonia_service, :github_export_target, :missing)

    on_exit(fn ->
      restore_env("SYMPHONIA_GITHUB_APP_ID", previous_app_id)
      restore_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH", previous_private_key)
      Application.delete_env(:symphonia_service, :github_client)
      Application.delete_env(:symphonia_service, :github_home)
      Application.delete_env(:symphonia_service, :github_export_target)
      Application.delete_env(:symphonia_service, :github_export_pr_state)
      File.rm_rf(root)
    end)

    repository =
      registry_path
      |> RepositoryRegistry.add(%{"path" => repo_path, "key" => "SYM"})
      |> Map.put("_registry_path", registry_path)
      |> Map.put("github", %{
        "owner" => "agora-creations",
        "name" => "symphonia",
        "url" => "https://github.com/agora-creations/symphonia",
        "default_branch" => "main",
        "installation_id" => 123,
        "auth_mode" => "app_installation"
      })

    InstallationStore.upsert_installation(%{
      "id" => 123,
      "account" => %{"login" => "agora-creations", "type" => "Organization"},
      "repositories" => [
        %{
          "owner" => "agora-creations",
          "name" => "symphonia",
          "repo_id" => 99,
          "url" => "https://github.com/agora-creations/symphonia",
          "default_branch" => "main"
        }
      ]
    })

    PrivateWorkspace.initialize(repository)

    artifact =
      PrivateWorkspace.create_artifact(repository, "decision", %{
        "title" => "Private Workspace Model",
        "body" => """
        # Private Workspace Model

        Public decision content.
        SECRET_TOKEN=value
        provider output should stay private.
        thread_id: abc123
        Local path: /Users/local/repo
        """
      })

    %{repository: repository, artifact: artifact}
  end

  test "renderer strips private metadata and risky content", %{
    repository: repository,
    artifact: artifact
  } do
    markdown =
      ExportRenderer.render(repository, "decision", artifact["id"], artifact["latestRevisionId"])

    assert markdown =~ "source: symphonia"
    assert markdown =~ "artifact_kind: decision"
    assert markdown =~ "Public decision content."
    refute markdown =~ "SECRET_TOKEN=value"
    refute markdown =~ "provider output"
    refute markdown =~ "thread_id"
    refute markdown =~ "/Users/local"
  end

  test "preview validates path policy and does not persist exports", %{
    repository: repository,
    artifact: artifact
  } do
    assert_raise ArgumentError, "GitHub target path is not allowed.", fn ->
      ExportPreview.preview(repository, "decision", artifact["id"], %{
        "revisionId" => artifact["latestRevisionId"],
        "targetPath" => ".github/workflows/export.yml",
        "baseBranch" => "main"
      })
    end

    preview =
      ExportPreview.preview(repository, "decision", artifact["id"], %{
        "revisionId" => artifact["latestRevisionId"],
        "targetPath" => "docs/symphonia/decisions/private-workspace-model.md",
        "baseBranch" => "main"
      })

    assert preview["operation"] == "create"
    assert preview["markdownPreview"] =~ "Private Workspace Model"
    assert ExportStore.list_for_artifact(repository, "decision", artifact["id"]) == []
  end

  test "opens pull request, stores exact revision, refreshes, and unlinks", %{
    repository: repository,
    artifact: artifact
  } do
    first_revision = artifact["latestRevisionId"]

    result =
      GitHubExporter.open_pr(repository, "decision", artifact["id"], %{
        "revisionId" => first_revision,
        "targetPath" => "docs/symphonia/decisions/private-workspace-model.md",
        "baseBranch" => "main"
      })

    export = result["export"]
    assert export["status"] == "pr_open"
    assert export["exportedRevisionId"] == first_revision
    assert export["pullRequestUrl"] == "https://github.com/agora-creations/symphonia/pull/123"
    assert result["artifact"]["exportStatus"] == "pr_open"

    assert_raise ArgumentError,
                 "An export pull request is already open for this artifact path.",
                 fn ->
                   GitHubExporter.open_pr(repository, "decision", artifact["id"], %{
                     "revisionId" => first_revision,
                     "targetPath" => "docs/symphonia/decisions/private-workspace-model.md",
                     "baseBranch" => "main"
                   })
                 end

    Application.put_env(:symphonia_service, :github_export_target, :exists)
    refreshed = GitHubExporter.refresh(repository, "decision", artifact["id"], export["id"])
    assert refreshed["export"]["status"] == "linked"
    assert refreshed["artifact"]["exportStatus"] == "linked"

    updated =
      PrivateWorkspace.update_artifact(repository, "decision", artifact["id"], %{
        "body" => "# Private Workspace Model\n\nChanged privately."
      })

    assert updated["exportStatus"] == "changed_since_export"

    unlinked = GitHubExporter.unlink(repository, "decision", artifact["id"], export["id"])
    assert unlinked["export"]["status"] == "unlinked"
    assert unlinked["artifact"]["exportStatus"] == "unlinked"
  end

  defp write_private_key!(path) do
    key = :public_key.generate_key({:rsa, 1024, 65_537})
    entry = :public_key.pem_entry_encode(:RSAPrivateKey, key)
    File.write!(path, :public_key.pem_encode([entry]))
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
