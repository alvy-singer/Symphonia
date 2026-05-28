defmodule SymphoniaService.RunStoreTest do
  use ExUnit.Case

  alias SymphoniaService.CodingAssistant.RunStore

  setup do
    root =
      Path.join(System.tmp_dir!(), "symphonia-run-store-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(root) end)
    %{root: root}
  end

  test "public run payload and progress events hide private provider details", %{root: root} do
    run =
      RunStore.create(
        %{
          "provider" => "codex_app_server",
          "repository" => "SYM",
          "task" => "SYM-1",
          "kind" => "daemon_assignment",
          "workspace_path" => "/Users/example/private/workspace",
          "codex_thread_id" => "thread-secret",
          "turn_id" => "turn-secret"
        },
        root: root
      )
      |> RunStore.mark_running(root: root)
      |> RunStore.mark_step("Starting Codex thread", root: root)
      |> RunStore.update_metadata(
        %{
          "review_branch" => "symphonia/task/sym-1",
          "curated_summary_path" => "symphonia/run-summaries/sym-1.md"
        },
        root: root
      )
      |> RunStore.mark_completed(%{"summary" => "Ready"}, root: root)

    public = RunStore.public(run)

    assert public["kind"] == "daemon_assignment"
    refute Map.has_key?(public, "workspacePath")
    refute Map.has_key?(public, "codexThreadId")
    refute Map.has_key?(public, "turnId")

    events = RunStore.public_progress_events(run)

    assert [%{"id" => first_id, "event" => "run-progress"} | _rest] = events
    assert Enum.any?(events, &(&1["displayStep"] == "Starting Codex thread"))
    assert Enum.any?(events, &(&1["state"] == "completed"))

    encoded = JSON.encode!(events)
    refute encoded =~ "/Users/example"
    refute encoded =~ "thread-secret"
    refute encoded =~ "turn-secret"

    replayed = RunStore.public_progress_events(run, after: first_id)
    assert length(replayed) == length(events) - 1
    refute Enum.any?(replayed, &(&1["id"] == first_id))
  end
end
