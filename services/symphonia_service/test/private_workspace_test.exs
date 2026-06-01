defmodule SymphoniaService.PrivateWorkspaceTest do
  use ExUnit.Case

  alias SymphoniaService.{PrivateWorkspace, RepositoryRegistry}
  alias SymphoniaService.Privacy.Inventory

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphonia-private-workspace-test-#{System.unique_integer([:positive])}"
      )

    repo_path = Path.join(root, "repo")
    registry_path = Path.join(root, "registry.json")
    File.mkdir_p!(Path.join(repo_path, ".git"))

    on_exit(fn -> File.rm_rf(root) end)

    repository =
      registry_path
      |> RepositoryRegistry.add(%{"path" => repo_path, "key" => "SYM"})
      |> Map.put("_registry_path", registry_path)

    %{root: root, registry_path: registry_path, repo_path: repo_path, repository: repository}
  end

  test "initializes private defaults outside the managed repository", %{
    repository: repository,
    repo_path: repo_path,
    registry_path: registry_path
  } do
    state = PrivateWorkspace.state(repository)

    refute state["initialized"]
    assert "codebase_map" in state["missingDefaultArtifacts"]

    initialized = PrivateWorkspace.initialize(repository)
    workspace_root = PrivateWorkspace.root(repository)

    assert initialized["initialized"]
    assert String.starts_with?(workspace_root, Path.dirname(registry_path))
    refute String.starts_with?(workspace_root, repo_path)
    refute File.exists?(Path.join(repo_path, "symphonia/codebase"))

    map = PrivateWorkspace.read_artifact(repository, "codebase_map", "codebase-map")
    assert map["path"] == "private-workspace/codebase_map/codebase-map"
    assert map["body"] =~ "# Codebase Map"
  end

  test "creates, reads, updates, and revisions private artifacts", %{repository: repository} do
    PrivateWorkspace.initialize(repository)

    artifact =
      PrivateWorkspace.create_artifact(repository, "milestone", %{
        "title" => "Private milestone",
        "body" => "# Private milestone\n"
      })

    first_revision = artifact["latestRevisionId"]

    updated =
      PrivateWorkspace.update_artifact(repository, "milestone", artifact["id"], %{
        "body" => "# Private milestone\n\nUpdated privately."
      })

    assert updated["body"] =~ "Updated privately."
    assert updated["latestRevisionId"] != first_revision
    assert length(updated["metadata"]["revisions"]) == 2

    metadata_only =
      PrivateWorkspace.update_artifact(repository, "milestone", artifact["id"], %{
        "metadata" => %{"title" => "Renamed private milestone"}
      })

    assert metadata_only["title"] == "Renamed private milestone"
    assert metadata_only["latestRevisionId"] == updated["latestRevisionId"]
    assert length(metadata_only["metadata"]["revisions"]) == 2

    assert PrivateWorkspace.read_artifact(repository, "milestone", artifact["id"])["body"] =~
             "Updated privately."
  end

  test "detects and imports supported legacy repo artifacts without mutating them", %{
    repository: repository,
    repo_path: repo_path
  } do
    map_path = Path.join(repo_path, "symphonia/codebase/map.md")
    milestone_path = Path.join(repo_path, "symphonia/milestones/milestone-001.md")
    unsupported_path = Path.join(repo_path, "symphonia/codebase/architecture.md")
    File.mkdir_p!(Path.dirname(map_path))
    File.mkdir_p!(Path.dirname(milestone_path))

    File.write!(map_path, "# Legacy map\n\nKeep this repo copy.")

    File.write!(milestone_path, """
    ---
    type: milestone
    id: milestone-001
    title: Legacy milestone
    status: approved
    ---

    # Legacy milestone
    """)

    File.write!(unsupported_path, "# Unsupported architecture\n")

    legacy = PrivateWorkspace.legacy_artifacts(repository)
    legacy_paths = Enum.map(legacy, & &1["legacyRepoPath"])

    assert "symphonia/codebase/map.md" in legacy_paths
    assert "symphonia/milestones/milestone-001.md" in legacy_paths
    refute "symphonia/codebase/architecture.md" in legacy_paths

    result = PrivateWorkspace.import_legacy(repository, %{"all" => true})
    assert result["count"] == 2

    imported = PrivateWorkspace.read_artifact(repository, "milestone", "milestone-001")
    assert imported["legacyRepoPath"] == "symphonia/milestones/milestone-001.md"
    assert imported["exportStatus"] == "linked"
    assert File.exists?(map_path)
    assert File.read!(milestone_path) =~ "Legacy milestone"

    PrivateWorkspace.update_artifact(repository, "milestone", "milestone-001", %{
      "body" => "# Private edit\n"
    })

    assert File.read!(milestone_path) =~ "Legacy milestone"

    assert PrivateWorkspace.read_artifact(repository, "milestone", "milestone-001")["body"] =~
             "Private edit"
  end

  test "records sanitized evidence and tracks manual export metadata", %{repository: repository} do
    PrivateWorkspace.initialize(repository)

    artifact =
      PrivateWorkspace.create_artifact(repository, "plan", %{
        "title" => "Exportable plan",
        "body" => "# Exportable plan\n"
      })

    [evidence] =
      PrivateWorkspace.record_validation_evidence(repository, %{"id" => "run-1"}, [
        %{
          "label" => "Build",
          "status" => "failed",
          "detail" => Enum.join(Inventory.risky_values(), " ")
        }
      ])

    encoded_evidence = JSON.encode!(evidence)
    assert evidence["kind"] == "validation_excerpt"

    for value <- Inventory.risky_values() do
      refute encoded_evidence =~ value
    end

    exported = PrivateWorkspace.export_artifact(repository, "plan", artifact["id"])
    assert exported["exportStatus"] == "linked"
    assert exported["reviewBranch"] =~ "symphonia/private-workspace/plan/"

    updated =
      PrivateWorkspace.update_artifact(repository, "plan", artifact["id"], %{
        "body" => "# Exportable plan\n\nChanged."
      })

    assert updated["exportStatus"] == "changed_since_export"
  end
end
