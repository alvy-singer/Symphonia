defmodule SymphoniaService.RepositoryRegistryTest do
  use ExUnit.Case

  alias SymphoniaService.RepositoryRegistry

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphonia-registry-test-#{System.unique_integer([:positive])}"
      )

    registry_path = Path.join(root, "registry.json")
    repo_path = Path.join(root, "repo")
    File.mkdir_p!(repo_path)

    on_exit(fn -> File.rm_rf(root) end)

    %{registry_path: registry_path, repo_path: repo_path}
  end

  test "rejects folders that are not Git repositories", %{
    registry_path: registry_path,
    repo_path: repo_path
  } do
    assert_raise ArgumentError, RepositoryRegistry.git_error(), fn ->
      RepositoryRegistry.add(registry_path, %{"path" => repo_path, "key" => "SYM"})
    end
  end

  test "adds and lists Git repositories", %{registry_path: registry_path, repo_path: repo_path} do
    File.mkdir_p!(Path.join(repo_path, ".git"))

    repository =
      RepositoryRegistry.add(registry_path, %{
        "path" => repo_path,
        "key" => "sym",
        "name" => "Symphonia"
      })

    assert repository["key"] == "SYM"
    assert repository["name"] == "Symphonia"
    assert repository["path"] == repo_path

    assert [stored] = RepositoryRegistry.list(registry_path)
    assert stored["key"] == "SYM"
  end

  test "removes repositories from the registry without deleting files", %{
    registry_path: registry_path,
    repo_path: repo_path
  } do
    File.mkdir_p!(Path.join(repo_path, ".git"))
    File.write!(Path.join(repo_path, "README.md"), "local worktree")

    RepositoryRegistry.add(registry_path, %{"path" => repo_path, "key" => "SYM"})
    removed = RepositoryRegistry.remove(registry_path, "sym")

    assert removed["key"] == "SYM"
    assert RepositoryRegistry.list(registry_path) == []
    assert File.exists?(Path.join(repo_path, "README.md"))
  end
end
