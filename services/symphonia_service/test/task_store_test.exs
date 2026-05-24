defmodule SymphoniaService.TaskStoreTest do
  use ExUnit.Case

  alias SymphoniaService.TaskStore

  test "applies an event and writes the same markdown file" do
    root = Path.join(System.tmp_dir!(), "symphonia-service-test-#{System.unique_integer([:positive])}")
    task_dir = Path.join([root, "SYM", "symphonia", "tasks"])
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

    updated = TaskStore.apply_event(root, "SYM", "SYM-120", "start")
    written = File.read!(task_path)

    assert updated["status"] == "in_progress"
    assert written =~ "status: in_progress"
    assert written =~ "Preserve this body."
  after
    if root = Process.get(:root), do: File.rm_rf(root)
  end
end
