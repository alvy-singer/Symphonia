defmodule SymphoniaService.TaskStoreTest do
  use ExUnit.Case

  alias SymphoniaService.{RepositoryRegistry, TaskStore, Workspace}

  setup do
    root =
      Path.join(System.tmp_dir!(), "symphonia-service-test-#{System.unique_integer([:positive])}")

    repo_path = Path.join(root, "repo")
    registry_path = Path.join(root, "registry.json")
    File.mkdir_p!(Path.join(repo_path, ".git"))

    on_exit(fn -> File.rm_rf(root) end)

    repository = RepositoryRegistry.add(registry_path, %{"path" => repo_path, "key" => "SYM"})
    %{root: root, repo_path: repo_path, registry_path: registry_path, repository: repository}
  end

  test "applies an event and writes the same markdown file", %{repo_path: repo_path} do
    repository = %{"key" => "SYM", "name" => "repo", "path" => repo_path, "last_task_number" => 0}
    task_dir = Path.join([repo_path, "symphonia", "tasks"])
    File.mkdir_p!(task_dir)

    task_path = Path.join(task_dir, "SYM-120.md")

    File.write!(task_path, """
    ---
    key: SYM-120
    title: Roundtrip task
    status: todo
    priority: high
    github_sync_enabled: true
    files_changed:
    updated_at: 2026-05-24T00:00:00Z
    ---

    # Roundtrip task

    Preserve this body.
    """)

    updated = TaskStore.apply_event(repository, "SYM-120", "start")
    written = File.read!(task_path)

    assert updated["status"] == "in_progress"
    assert written =~ "status: in_progress"
    assert written =~ "Preserve this body."
  end

  test "creates tasks with collision-safe keys", %{
    registry_path: registry_path,
    repository: repository,
    repo_path: repo_path
  } do
    Workspace.initialize(repository)
    task_dir = Path.join([repo_path, "symphonia", "tasks"])

    File.write!(Path.join(task_dir, "SYM-1.md"), """
    ---
    key: SYM-1
    title: Existing one
    status: todo
    priority: no-priority
    ---

    # Existing one
    """)

    File.write!(Path.join(task_dir, "other.md"), """
    ---
    key: SYM-7
    title: Existing seven
    status: todo
    priority: no-priority
    ---

    # Existing seven
    """)

    task = TaskStore.create_task(registry_path, repository, %{"title" => "New task"})

    assert task["key"] == "SYM-8"
    assert File.exists?(Path.join(task_dir, "SYM-8.md"))

    repository = RepositoryRegistry.get!(registry_path, "SYM")
    File.rm!(Path.join(task_dir, "SYM-8.md"))

    next_task = TaskStore.create_task(registry_path, repository, %{"title" => "Next task"})
    assert next_task["key"] == "SYM-9"
  end
end
