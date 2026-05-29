defmodule SymphoniaService.AuditLogTest do
  use ExUnit.Case

  alias SymphoniaService.Access.AuditLog

  setup do
    root = Path.join(System.tmp_dir!(), "symphonia-audit-#{System.unique_integer([:positive])}")
    registry_path = Path.join(root, "repositories.json")
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    %{
      registry_path: registry_path,
      repository: %{"key" => "SYM"}
    }
  end

  test "records public-safe events beside registry state", %{
    registry_path: registry_path,
    repository: repository
  } do
    event =
      AuditLog.record(registry_path, repository, %{
        "actor" => %{"id" => "ava", "name" => "Ava", "role" => "maintainer"},
        "action" => "pull_request.open",
        "target" => %{"type" => "task", "id" => "SYM-1"},
        "result" => "completed",
        "summary" => "Ava opened a pull request for SYM-1.",
        "metadata" => %{
          "taskKey" => "SYM-1",
          "runId" => "run_123",
          "threadId" => "thread_secret",
          "workspacePath" => "/Users/ava/private/repo",
          "provider" => "codex_app_server",
          "rawProviderOutput" => "secret"
        }
      })

    assert event["metadata"] == %{
             "provider" => "codex_app_server",
             "runId" => "run_123",
             "taskKey" => "SYM-1"
           }

    assert AuditLog.path(registry_path) ==
             Path.join([Path.dirname(registry_path), "audit", "events.jsonl"])

    assert File.exists?(AuditLog.path(registry_path))
  end

  test "task audit filters by task key and listing respects limit", %{
    registry_path: registry_path,
    repository: repository
  } do
    first =
      AuditLog.record(registry_path, repository, %{
        "actor" => %{"id" => "ava", "name" => "Ava", "role" => "maintainer"},
        "action" => "task.run_codex",
        "target" => %{"type" => "task", "id" => "SYM-1"},
        "result" => "completed",
        "metadata" => %{"taskKey" => "SYM-1"}
      })

    second =
      AuditLog.record(registry_path, repository, %{
        "actor" => %{"id" => "ava", "name" => "Ava", "role" => "maintainer"},
        "action" => "task.run_codex",
        "target" => %{"type" => "task", "id" => "SYM-2"},
        "result" => "completed",
        "metadata" => %{"taskKey" => "SYM-2"}
      })

    assert first["id"] != second["id"]
    assert first["id"] < second["id"]
    assert [^second] = AuditLog.list(registry_path, repository, limit: 1)
    assert [^first] = AuditLog.list_for_task(registry_path, repository, "SYM-1")
  end

  test "sanitizer redacts allowed string values and drops unknown keys" do
    assert AuditLog.sanitize_metadata(%{
             "reviewBranch" => "/Users/ava/repo/branch",
             "githubPrUrl" => "TOKEN=secret",
             "sandboxId" => "sandbox-123",
             "turnId" => "turn-123"
           }) == %{
             "githubPrUrl" => "[environment value hidden]",
             "reviewBranch" => "[local path hidden]"
           }
  end
end
