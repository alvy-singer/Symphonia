defmodule SymphoniaService.CodexAppServerProviderTest do
  use ExUnit.Case

  alias SymphoniaService.Clarise.{MilestoneLoop, PlanToTaskCompiler}
  alias SymphoniaService.CodingAssistant.{AppServerClient, RunStore}
  alias SymphoniaService.GitHub.InstallationStore
  alias SymphoniaService.Harness.{Automation, Daemon, Eligibility}
  alias SymphoniaService.Runner.LocalGitWorktreeProvider

  alias SymphoniaService.{
    CodingAssistant,
    PrivateWorkspace,
    RepositoryRegistry,
    TaskStore,
    Workspace
  }

  defmodule StubClient do
    def create_installation_token(_jwt, _installation_id) do
      {:ok,
       %{
         "token" => "installation-token",
         "expires_at" =>
           DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
       }}
    end
  end

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphonia-codex-app-server-provider-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    private_key_path = Path.join(root, "github-app.pem")
    write_private_key!(private_key_path)

    %{remote_path: remote_path, repo_path: repo_path} = setup_git!(root)

    registry_path = Path.join(root, "registry.json")
    github_home = Path.join(root, "github")
    runs_root = Path.join(root, "runs")
    workspaces_root = Path.join(root, "workspaces")
    fake_app_server = Path.join(root, "fake-app-server.js")
    requests_file = Path.join(root, "app-server-requests.json")
    args_file = Path.join(root, "app-server-args.json")

    write_fake_app_server!(fake_app_server)

    previous_app_id = System.get_env("SYMPHONIA_GITHUB_APP_ID")
    previous_private_key = System.get_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH")
    previous_runs_root = System.get_env("SYMPHONIA_RUNS_ROOT")
    previous_workspaces_root = System.get_env("SYMPHONIA_WORKSPACES_ROOT")
    previous_skip_daemon = System.get_env("SYMPHONIA_CODEX_APP_SERVER_SKIP_DAEMON")
    previous_app_server_command = System.get_env("SYMPHONIA_CODEX_APP_SERVER_COMMAND")
    previous_app_server_args = System.get_env("SYMPHONIA_CODEX_APP_SERVER_ARGS")
    previous_standalone_bin = System.get_env("SYMPHONIA_CODEX_APP_SERVER_STANDALONE_BIN")
    previous_codex_bin = System.get_env("SYMPHONIA_CODEX_BIN")
    previous_app_server_bin = System.get_env("SYMPHONIA_CODEX_APP_SERVER_BIN")
    previous_startup_timeout = System.get_env("SYMPHONIA_CODEX_STARTUP_TIMEOUT_MS")
    previous_workspace_provider = System.get_env("SYMPHONIA_WORKSPACE_PROVIDER")
    previous_experimental_sandbox = System.get_env("SYMPHONIA_EXPERIMENTAL_SANDBOX_PROVIDER")
    previous_sandboxes_root = System.get_env("SYMPHONIA_SANDBOXES_ROOT")
    previous_requests_file = System.get_env("FAKE_APP_SERVER_REQUESTS_FILE")
    previous_args_file = System.get_env("FAKE_APP_SERVER_ARGS_FILE")
    previous_fake_mode = System.get_env("FAKE_APP_SERVER_MODE")
    previous_output_suffix = System.get_env("FAKE_APP_SERVER_OUTPUT_SUFFIX")
    previous_excluded_write = System.get_env("FAKE_APP_SERVER_WRITE_EXCLUDED")

    System.put_env("SYMPHONIA_GITHUB_APP_ID", "42")
    System.put_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH", private_key_path)
    System.put_env("SYMPHONIA_RUNS_ROOT", runs_root)
    System.put_env("SYMPHONIA_WORKSPACES_ROOT", workspaces_root)
    System.put_env("SYMPHONIA_CODEX_APP_SERVER_SKIP_DAEMON", "true")
    System.put_env("SYMPHONIA_CODEX_APP_SERVER_COMMAND", fake_app_server)
    System.put_env("SYMPHONIA_SANDBOXES_ROOT", Path.join(root, "sandboxes"))
    System.delete_env("SYMPHONIA_WORKSPACE_PROVIDER")
    System.delete_env("SYMPHONIA_EXPERIMENTAL_SANDBOX_PROVIDER")
    System.put_env("FAKE_APP_SERVER_REQUESTS_FILE", requests_file)
    System.put_env("FAKE_APP_SERVER_ARGS_FILE", args_file)

    Application.put_env(:symphonia_service, :github_client, StubClient)
    Application.put_env(:symphonia_service, :github_home, github_home)

    on_exit(fn ->
      restore_env("SYMPHONIA_GITHUB_APP_ID", previous_app_id)
      restore_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH", previous_private_key)
      restore_env("SYMPHONIA_RUNS_ROOT", previous_runs_root)
      restore_env("SYMPHONIA_WORKSPACES_ROOT", previous_workspaces_root)
      restore_env("SYMPHONIA_CODEX_APP_SERVER_SKIP_DAEMON", previous_skip_daemon)
      restore_env("SYMPHONIA_CODEX_APP_SERVER_COMMAND", previous_app_server_command)
      restore_env("SYMPHONIA_CODEX_APP_SERVER_ARGS", previous_app_server_args)
      restore_env("SYMPHONIA_CODEX_APP_SERVER_STANDALONE_BIN", previous_standalone_bin)
      restore_env("SYMPHONIA_CODEX_BIN", previous_codex_bin)
      restore_env("SYMPHONIA_CODEX_APP_SERVER_BIN", previous_app_server_bin)
      restore_env("SYMPHONIA_CODEX_STARTUP_TIMEOUT_MS", previous_startup_timeout)
      restore_env("SYMPHONIA_WORKSPACE_PROVIDER", previous_workspace_provider)
      restore_env("SYMPHONIA_EXPERIMENTAL_SANDBOX_PROVIDER", previous_experimental_sandbox)
      restore_env("SYMPHONIA_SANDBOXES_ROOT", previous_sandboxes_root)
      restore_env("FAKE_APP_SERVER_REQUESTS_FILE", previous_requests_file)
      restore_env("FAKE_APP_SERVER_ARGS_FILE", previous_args_file)
      restore_env("FAKE_APP_SERVER_MODE", previous_fake_mode)
      restore_env("FAKE_APP_SERVER_OUTPUT_SUFFIX", previous_output_suffix)
      restore_env("FAKE_APP_SERVER_WRITE_EXCLUDED", previous_excluded_write)
      Application.delete_env(:symphonia_service, :github_client)
      Application.delete_env(:symphonia_service, :github_home)
      File.rm_rf(root)
    end)

    repository = RepositoryRegistry.add(registry_path, %{"path" => repo_path, "key" => "SYM"})
    Workspace.initialize(repository)
    Workspace.create_workflow_from_template(repository, "review-first")

    InstallationStore.upsert_installation(%{
      "id" => 123,
      "account" => %{"login" => "agora-creations", "type" => "Organization"},
      "repositories" => [
        %{
          "owner" => "agora-creations",
          "name" => "symphonia",
          "repo_id" => 99,
          "url" => "https://github.com/agora-creations/symphonia",
          "clone_url" => remote_path,
          "default_branch" => "main"
        }
      ]
    })

    repository =
      RepositoryRegistry.update(registry_path, "SYM", fn repo ->
        Map.put(repo, "github", %{
          "owner" => "agora-creations",
          "name" => "symphonia",
          "repo_id" => 99,
          "url" => "https://github.com/agora-creations/symphonia",
          "clone_url" => remote_path,
          "default_branch" => "main",
          "installation_id" => 123,
          "auth_mode" => "app_installation"
        })
      end)

    milestone = approved_milestone(repository)
    PlanToTaskCompiler.propose(repository, milestone["id"])
    PlanToTaskCompiler.create_tasks(registry_path, repository, milestone["id"])
    repository = Automation.enable(registry_path, "SYM")

    %{
      registry_path: registry_path,
      fake_app_server: fake_app_server,
      args_file: args_file,
      remote_path: remote_path,
      repository: repository,
      requests_file: requests_file,
      runs_root: runs_root,
      workspaces_root: workspaces_root
    }
  end

  test "daemon dispatches an eligible task through fake Codex App Server", %{
    registry_path: registry_path,
    remote_path: remote_path,
    repository: repository,
    requests_file: requests_file,
    runs_root: runs_root,
    workspaces_root: workspaces_root
  } do
    name = :"harness_daemon_test_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Daemon.start_link(registry_path: registry_path, timer?: false, name: name)

    result = Daemon.tick(name)

    assert [%{"code" => "dispatched", "dispatched" => true} | _rest] = result["decisions"]
    assert Enum.count(result["decisions"], & &1["dispatched"]) == 1
    assert result["limits"]["maxClaimsPerTick"] == 1
    assert result["limits"]["maxClaimsPerRepo"] == 1
    assert result["limits"]["maxConcurrentRuns"] == 1
    assert result["lastHeartbeatAt"]
    assert result["lastDispatch"]["task"] == "SYM-1"
    assert result["providerReadiness"]["runnableProvider"] == "codex_app_server"

    second_result = Daemon.tick(name)
    refute Enum.any?(second_result["decisions"], &(&1["task"] == "SYM-1" and &1["dispatched"]))

    [task | _rest] = TaskStore.list_tasks(repository)
    run = wait_for_latest_run(runs_root, "completed")
    task = wait_for_task_status(repository, task["key"], "in_review")

    assert run["provider"] == "codex_app_server"
    assert run["kind"] == "daemon_assignment"
    assert task["run"]["kind"] == "daemon_assignment"
    assert run["workspace_path"] == Path.join([workspaces_root, "sym", "sym-1"])
    assert run["codex_thread_id"] == "thread-fake"
    assert run["turn_id"] == "turn-fake"
    assert run["curated_summary_id"] == "sym-1-codex-handoff"
    assert run["curated_summary_path"] == "private-workspace/run_summary/sym-1-codex-handoff"
    assert run["provider_output"]["app_server_events"] != []
    assert task["handoff"]["curatedSummaryPath"] == run["curated_summary_path"]
    assert task["handoff"]["curatedSummaryId"] == run["curated_summary_id"]
    assert "app/app-server-output.txt" in task["handoff"]["filesChanged"]
    refute run["curated_summary_path"] in task["handoff"]["filesChanged"]
    assert task["handoff"]["summary"] == "Fake App Server changed app/app-server-output.txt."
    assert task["handoff"]["headBranch"] == "symphonia/task/sym-1"
    assert task["handoff"]["baseBranch"] == "main"

    assert task["handoff"]["nextReviewAction"] ==
             "Review the changed files and approve them to open a pull request."

    assert [
             %{
               "label" => "Machine validation",
               "status" => "not_run",
               "detail" => "No machine validation command was configured."
             }
           ] = task["handoff"]["validationEvidence"]

    branch_files =
      git_output!([
        "--git-dir",
        remote_path,
        "ls-tree",
        "-r",
        "--name-only",
        "refs/heads/symphonia/task/sym-1"
      ])

    assert branch_files =~ "app/app-server-output.txt"
    refute branch_files =~ run["curated_summary_path"]

    summary =
      PrivateWorkspace.read_artifact(
        private_repository(repository, registry_path),
        "run_summary",
        run["curated_summary_id"]
      )

    summary_body = summary["body"]

    assert summary_body =~ "Machine validation: Not run"
    refute branch_files =~ "symphonia/tasks/SYM-1.md"

    assert summary_body =~ "Raw app-server events remain in the local Symphonía run store."
    assert summary_body =~ "## Validation Evidence"
    refute summary_body =~ "turn/completed"
    refute summary_body =~ "thread-fake"
    refute summary_body =~ "turn-fake"

    requests = JSON.decode!(File.read!(requests_file))
    assert Enum.any?(requests, &(&1["method"] == "thread/start"))
    assert Enum.any?(requests, &(&1["method"] == "turn/start"))

    turn_start = Enum.find(requests, &(&1["method"] == "turn/start"))
    assert turn_start["params"]["approvalPolicy"] == "never"
    assert turn_start["params"]["cwd"] == run["workspace_path"]

    [%{"text" => prompt}] = turn_start["params"]["input"]
    assert prompt =~ "persistent task workspace"
    assert prompt =~ "Task key: #{task["key"]}"
    assert prompt =~ "WORKFLOW.md:"
    assert prompt =~ "Review expectations:"
    refute prompt =~ "thread-fake"
    refute prompt =~ "turn-fake"
    refute prompt =~ "turn/completed"

    review_blocked_task =
      TaskStore.patch_task(repository, task["key"], %{
        "frontmatter" => %{
          "depends_on" => [],
          "handoff" => %{},
          "run" => %{"state" => "completed"},
          "status" => "todo"
        }
      })

    review_branch_explanation = Eligibility.explain(repository, review_blocked_task)
    assert review_branch_explanation["eligible"] == false
    assert review_branch_explanation["code"] == "review_branch_exists"
  end

  test "daemon does not claim a task while a global active run exists", %{
    registry_path: registry_path,
    repository: repository,
    runs_root: runs_root
  } do
    [task | _rest] = TaskStore.list_tasks(repository)

    RunStore.create(
      %{
        "provider" => "codex_app_server",
        "repository" => repository["key"],
        "task" => task["key"]
      },
      root: runs_root
    )

    name = :"harness_daemon_active_run_test_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Daemon.start_link(registry_path: registry_path, timer?: false, name: name)

    result = Daemon.tick(name)

    refute Enum.any?(result["decisions"], & &1["dispatched"])
    assert [%{"code" => "max_concurrent_runs_reached"} | _rest] = result["decisions"]
  end

  test "Harness run ignores requested provider and uses Codex App Server", %{
    registry_path: registry_path,
    repository: repository,
    runs_root: runs_root
  } do
    [task | _rest] = TaskStore.list_tasks(repository)
    System.put_env("SYMPHONIA_EXPERIMENTAL_SANDBOX_PROVIDER", "1")
    System.put_env("SYMPHONIA_WORKSPACE_PROVIDER", "experimental_sandbox")

    result =
      CodingAssistant.start_harness_run(registry_path, repository, task["key"], %{
        "provider" => "claude_code",
        "workspace_provider" => "experimental_sandbox",
        "eligibility_reason" => "Provider lock invariant."
      })

    run = wait_for_run(runs_root, result["run"]["id"], "completed")

    assert result["run"]["provider"] == "codex_app_server"
    assert run["provider"] == "codex_app_server"
    assert run["workspace_provider"] == "local_git_worktree"
    assert run["handoff"]["head_branch"] == "symphonia/task/sym-1"
  end

  test "harness pause persists and blocks manual tick", %{
    registry_path: registry_path
  } do
    name = :"harness_daemon_pause_test_#{System.unique_integer([:positive])}"
    {:ok, pid} = Daemon.start_link(registry_path: registry_path, timer?: false, name: name)

    paused = Daemon.pause(name)
    assert paused["paused"] == true
    assert [%{"code" => "harness_paused", "kind" => "pause"}] = paused["decisions"]

    tick = Daemon.tick(name)
    assert tick["paused"] == true
    refute Enum.any?(tick["decisions"], &(&1["dispatched"] == true))
    assert Enum.any?(tick["decisions"], &(&1["code"] == "harness_paused"))

    GenServer.stop(pid)

    restarted_name = :"harness_daemon_pause_restart_test_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      Daemon.start_link(registry_path: registry_path, timer?: false, name: restarted_name)

    assert Daemon.status(restarted_name)["paused"] == true
    assert Daemon.resume(restarted_name)["paused"] == false
    assert Daemon.status(restarted_name)["paused"] == false
  end

  test "daemon startup reconciles stale active run before dispatch", %{
    registry_path: registry_path,
    repository: repository,
    runs_root: runs_root
  } do
    [task | _rest] = TaskStore.list_tasks(repository)

    stale_at = DateTime.utc_now() |> DateTime.add(-7200, :second) |> DateTime.to_iso8601()

    run =
      RunStore.create(
        %{
          "provider" => "codex_app_server",
          "repository" => repository["key"],
          "task" => task["key"],
          "kind" => "daemon_assignment"
        },
        root: runs_root
      )
      |> RunStore.mark_running(root: runs_root)
      |> Map.merge(%{"started_at" => stale_at, "updated_at" => stale_at})

    rewrite_run!(runs_root, run)

    TaskStore.apply_event(repository, task["key"], "start")

    TaskStore.patch_task(repository, task["key"], %{
      "frontmatter" => %{"run" => task_run_frontmatter(run)}
    })

    name = :"harness_daemon_reconcile_start_test_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      Daemon.start_link(
        registry_path: registry_path,
        timer?: false,
        name: name,
        running_stale_after_ms: 0,
        heartbeat_stale_after_ms: 0
      )

    reconciled_run = RunStore.get(run["id"], root: runs_root)
    reconciled_task = TaskStore.get_task(repository, task["key"])

    assert reconciled_run["state"] == "failed"
    assert reconciled_task["status"] == "paused"
    assert reconciled_task["pausedReason"] == "run_failed"
    assert Daemon.status(name)["lastReconciliation"]["stale"] >= 1

    tick = Daemon.tick(name)
    refute Enum.any?(tick["decisions"], &(&1["code"] == "dispatched"))
  end

  test "due retry creates a linked daemon run before normal eligibility", %{
    registry_path: registry_path,
    repository: repository,
    runs_root: runs_root
  } do
    [task | _rest] = TaskStore.list_tasks(repository)
    failed_run = retryable_failed_run!(repository, task, runs_root, -30)

    name = :"harness_daemon_due_retry_test_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Daemon.start_link(registry_path: registry_path, timer?: false, name: name)

    result = Daemon.tick(name)

    assert Enum.any?(result["decisions"], &(&1["code"] == "retry_dispatched"))

    retried_run =
      runs_root
      |> Path.join("run_*.json")
      |> Path.wildcard()
      |> Enum.map(&(File.read!(&1) |> JSON.decode!()))
      |> Enum.find(&(&1["retry_of"] == failed_run["id"]))

    assert retried_run["attempt"] == 1
    assert retried_run["max_attempts"] == 2

    wait_for_run(runs_root, retried_run["id"], "completed")
  end

  test "retry waits for retryAt and respects harness pause", %{
    registry_path: registry_path,
    repository: repository,
    runs_root: runs_root
  } do
    [task | _rest] = TaskStore.list_tasks(repository)
    failed_run = retryable_failed_run!(repository, task, runs_root, 120)

    name = :"harness_daemon_retry_wait_test_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Daemon.start_link(registry_path: registry_path, timer?: false, name: name)

    future_tick = Daemon.tick(name)
    refute Enum.any?(future_tick["decisions"], &(&1["code"] == "retry_dispatched"))

    failed_run =
      failed_run
      |> Map.put(
        "retry_at",
        DateTime.utc_now() |> DateTime.add(-30, :second) |> DateTime.to_iso8601()
      )
      |> tap(&rewrite_run!(runs_root, &1))

    Daemon.pause(name)
    paused_tick = Daemon.tick(name)
    refute Enum.any?(paused_tick["decisions"], &(&1["code"] == "retry_dispatched"))

    assert RunStore.get(failed_run["id"], root: runs_root)["retry_at"]
  end

  test "retry is skipped when a handoff appears before retryAt", %{
    registry_path: registry_path,
    repository: repository,
    runs_root: runs_root
  } do
    [task | _rest] = TaskStore.list_tasks(repository)
    failed_run = retryable_failed_run!(repository, task, runs_root, -30)

    TaskStore.patch_task(repository, task["key"], %{
      "frontmatter" => %{
        "status" => "in_review",
        "handoff" => %{
          "summary" => "Ready",
          "files_changed" => ["app/file.ts"],
          "next_review_action" => "Review."
        }
      }
    })

    name = :"harness_daemon_retry_handoff_test_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Daemon.start_link(registry_path: registry_path, timer?: false, name: name)

    result = Daemon.tick(name)
    refute Enum.any?(result["decisions"], &(&1["code"] == "retry_dispatched"))
    assert Enum.any?(result["decisions"], &(&1["code"] == "retry_no_longer_allowed"))
    refute RunStore.get(failed_run["id"], root: runs_root)["retry_at"]
  end

  test "exhausted transient daemon retry budget pauses without another retry", %{
    registry_path: registry_path,
    repository: repository,
    runs_root: runs_root
  } do
    [task | _rest] = TaskStore.list_tasks(repository)
    System.put_env("FAKE_APP_SERVER_MODE", "silent_initialize")
    System.put_env("SYMPHONIA_CODEX_STARTUP_TIMEOUT_MS", "250")

    result =
      CodingAssistant.start_harness_run(registry_path, repository, task["key"], %{
        "eligibility_reason" => "Retrying transient Harness failure.",
        "attempt" => 2,
        "max_attempts" => 2
      })

    run = wait_for_run(runs_root, result["run"]["id"], "failed")
    task = wait_for_task_status(repository, task["key"], "paused")

    assert run["failure_class"] == "transient_provider"
    refute run["retry_at"]
    assert run["message"] =~ "reached the retry limit"
    assert task["pausedReason"] == "run_failed"
    assert task["pausedExplanation"] =~ "reached the retry limit"
  end

  test "local workspace provider release preserves persistent task worktree", %{
    repository: repository
  } do
    [task | _rest] = TaskStore.list_tasks(repository)

    assert {:ok, context} = LocalGitWorktreeProvider.prepare(repository, task, %{}, %{})
    sentinel_path = Path.join(context.repo_path, ".symphonia-release-sentinel")
    File.write!(sentinel_path, "preserved")

    assert context.base_branch == "main"
    assert context.head_branch == "symphonia/task/sym-1"
    assert context.source_repo_path == repository["path"]
    assert context.persistent == true
    assert context.workspace_provider == "local_git_worktree"
    assert File.dir?(context.repo_path)

    assert :ok = LocalGitWorktreeProvider.release(context, %{})
    assert File.dir?(context.repo_path)
    assert File.read!(sentinel_path) == "preserved"
  end

  test "manual sandbox run imports changes into the local review workspace", %{
    registry_path: registry_path,
    remote_path: remote_path,
    repository: repository,
    requests_file: requests_file,
    runs_root: runs_root,
    workspaces_root: workspaces_root
  } do
    [task | _rest] = TaskStore.list_tasks(repository)
    review_path = Path.join([workspaces_root, "sym", "sym-1"])

    commit_workflow_validation!(
      repository["path"],
      "Review workspace validation",
      ~s|case "$PWD" in */workspaces/sym/sym-1) test -f app/app-server-output.txt ;; *) exit 1 ;; esac|
    )

    System.put_env("SYMPHONIA_EXPERIMENTAL_SANDBOX_PROVIDER", "1")

    result =
      CodingAssistant.start_run(registry_path, repository, task["key"], %{
        "workspace_provider" => "experimental_sandbox"
      })

    run = wait_for_run(runs_root, result["run"]["id"], "completed")
    task = wait_for_task_status(repository, task["key"], "in_review")
    public_run = CodingAssistant.get_run(repository, task["key"], run["id"])

    assert run["workspace_provider"] == "experimental_sandbox"
    assert run["workspace_path"] =~ "/sandboxes/"
    assert run["workspace_path"] != review_path
    refute File.exists?(run["workspace_path"])

    assert public_run["workspaceProvider"] == "experimental_sandbox"
    refute Map.has_key?(public_run, "workspacePath")
    refute inspect(public_run) =~ "sandbox_"
    refute inspect(public_run) =~ run["workspace_path"]

    assert task["run"]["workspaceProvider"] == "experimental_sandbox"
    assert task["handoff"]["headBranch"] == "symphonia/task/sym-1"
    assert "app/app-server-output.txt" in task["handoff"]["filesChanged"]

    assert File.read!(Path.join(review_path, "app/app-server-output.txt")) =~
             "Fake App Server work product"

    assert get_in(run, ["provider_output", "workspace", "sandbox", "sandbox_id"]) =~
             "sandbox_sym-1"

    assert get_in(run, ["provider_output", "sandbox_change_detection", "committable"]) == [
             "app/app-server-output.txt"
           ]

    assert [
             %{
               "label" => "Review workspace validation",
               "status" => "passed"
             }
           ] = get_in(run, ["provider_output", "validation", "results"])

    requests = JSON.decode!(File.read!(requests_file))
    turn_start = Enum.find(requests, &(&1["method"] == "turn/start"))
    assert turn_start["params"]["cwd"] == run["workspace_path"]

    [%{"text" => prompt}] = turn_start["params"]["input"]
    assert prompt =~ "Workspace path: #{run["workspace_path"]}"
    refute prompt =~ "Workspace path: #{review_path}"

    branch_files =
      git_output!([
        "--git-dir",
        remote_path,
        "ls-tree",
        "-r",
        "--name-only",
        "refs/heads/symphonia/task/sym-1"
      ])

    assert branch_files =~ "app/app-server-output.txt"
    refute branch_files =~ run["curated_summary_path"]

    summary =
      PrivateWorkspace.read_artifact(
        private_repository(repository, registry_path),
        "run_summary",
        run["curated_summary_id"]
      )["body"]

    refute summary =~ "sandbox_"
    refute summary =~ run["workspace_path"]
  end

  test "created Markdown task can start a Codex App Server-backed run", %{
    registry_path: registry_path,
    repository: repository,
    runs_root: runs_root
  } do
    task =
      TaskStore.create_task(registry_path, repository, %{
        "title" => "Manual Codex task",
        "body" => "Create a small app-server output file.",
        "review_expectations" => [
          "Changed files match the task request.",
          "Reviewer can inspect the generated output."
        ]
      })

    result = CodingAssistant.start_run(registry_path, repository, task["key"])
    run = wait_for_run(runs_root, result["run"]["id"], "completed")
    task = wait_for_task_status(repository, task["key"], "in_review")

    assert run["provider"] == "codex_app_server"
    assert task["handoff"]["headBranch"] == "symphonia/task/#{String.downcase(task["key"])}"
    assert "app/app-server-output.txt" in task["handoff"]["filesChanged"]

    assert [
             %{
               "label" => "Machine validation",
               "status" => "not_run",
               "detail" => "No machine validation command was configured."
             }
           ] = task["handoff"]["validationEvidence"]
  end

  test "Codex App Server run attaches passing workflow validation evidence", %{
    registry_path: registry_path,
    repository: repository,
    runs_root: runs_root
  } do
    commit_workflow_validation!(
      repository["path"],
      "Smoke validation",
      "test -f app/app-server-output.txt && printf APP_TOKEN=secret:/Users/example/private"
    )

    [task | _rest] = TaskStore.list_tasks(repository)
    result = CodingAssistant.start_run(registry_path, repository, task["key"])
    run = wait_for_run(runs_root, result["run"]["id"], "completed")
    task = wait_for_task_status(repository, task["key"], "in_review")

    assert [
             %{
               "label" => "Smoke validation",
               "status" => "passed",
               "detail" => "Smoke validation passed."
             }
           ] = task["handoff"]["validationEvidence"]

    validation = run["provider_output"]["validation"]
    assert validation["policy"]["source"] == "workflow"
    assert [%{"output" => private_output}] = validation["results"]
    assert private_output =~ "APP_TOKEN=secret:/Users/example/private"

    summary =
      PrivateWorkspace.read_artifact(
        private_repository(repository, registry_path),
        "run_summary",
        run["curated_summary_id"]
      )["body"]

    assert summary =~ "Smoke validation: Passed - Smoke validation passed."
    refute summary =~ "APP_TOKEN=secret"
    refute summary =~ "/Users/example/private"
  end

  test "failed required validation keeps handoff in review with warning evidence", %{
    registry_path: registry_path,
    repository: repository,
    runs_root: runs_root
  } do
    commit_workflow_validation!(
      repository["path"],
      "Required tests",
      "printf APP_SECRET=hidden:/Users/example/private && exit 2"
    )

    [task | _rest] = TaskStore.list_tasks(repository)
    result = CodingAssistant.start_run(registry_path, repository, task["key"])
    run = wait_for_run(runs_root, result["run"]["id"], "completed")
    task = wait_for_task_status(repository, task["key"], "in_review")

    assert task["handoff"]["nextReviewAction"] ==
             "Review the failed validation before approving. Request changes if Codex should fix it."

    assert [
             %{
               "label" => "Required tests",
               "status" => "failed",
               "detail" => "Required tests failed. Review the private run output locally."
             }
           ] = task["handoff"]["validationEvidence"]

    assert get_in(run, ["provider_output", "validation", "results", Access.at(0), "output"]) =~
             "APP_SECRET=hidden:/Users/example/private"

    summary =
      PrivateWorkspace.read_artifact(
        private_repository(repository, registry_path),
        "run_summary",
        run["curated_summary_id"]
      )["body"]

    assert summary =~
             "Required tests: Failed - Required tests failed. Review the private run output locally."

    refute summary =~ "APP_SECRET=hidden"
    refute summary =~ "/Users/example/private"
  end

  test "validation runs after excluded paths are reverted", %{
    registry_path: registry_path,
    repository: repository,
    runs_root: runs_root
  } do
    commit_workflow_validation!(
      repository["path"],
      "Excluded cleanup",
      "test ! -e symphonia/tasks/SYM-1.md"
    )

    System.put_env("FAKE_APP_SERVER_WRITE_EXCLUDED", "symphonia/tasks/SYM-1.md")

    [task | _rest] = TaskStore.list_tasks(repository)
    result = CodingAssistant.start_run(registry_path, repository, task["key"])
    wait_for_run(runs_root, result["run"]["id"], "completed")
    task = wait_for_task_status(repository, task["key"], "in_review")

    assert [
             %{
               "label" => "Excluded cleanup",
               "status" => "passed",
               "detail" => "Excluded cleanup passed."
             }
           ] = task["handoff"]["validationEvidence"]
  end

  test "missing managed Codex standalone pauses task with clear setup blocker and remains retryable",
       %{
         fake_app_server: fake_app_server,
         registry_path: registry_path,
         remote_path: remote_path,
         repository: repository,
         runs_root: runs_root,
         workspaces_root: workspaces_root
       } do
    missing_bin = Path.join(workspaces_root, "missing-codex-standalone")

    System.delete_env("SYMPHONIA_CODEX_APP_SERVER_SKIP_DAEMON")
    System.delete_env("SYMPHONIA_CODEX_APP_SERVER_COMMAND")
    System.delete_env("SYMPHONIA_CODEX_BIN")
    System.delete_env("SYMPHONIA_CODEX_APP_SERVER_BIN")
    System.put_env("SYMPHONIA_CODEX_APP_SERVER_STANDALONE_BIN", missing_bin)

    task =
      TaskStore.create_task(registry_path, repository, %{
        "title" => "Manual Codex setup blocker task",
        "body" => "Create a small app-server output file."
      })

    result = CodingAssistant.start_run(registry_path, repository, task["key"])
    run = wait_for_run(runs_root, result["run"]["id"], "failed")
    blocked_task = wait_for_task_status(repository, task["key"], "paused")

    assert run["message"] == AppServerClient.setup_blocker_message()
    assert run["error"] == AppServerClient.setup_blocker_message()
    refute Map.has_key?(run, "workspace_path")
    refute Map.has_key?(run, "codex_thread_id")
    refute Map.has_key?(run, "turn_id")
    refute Map.has_key?(run, "curated_summary_path")
    assert is_nil(blocked_task["handoff"])
    assert blocked_task["pausedReason"] == "blocked_by_setup"
    assert blocked_task["pausedExplanation"] == AppServerClient.setup_blocker_message()

    workspace_path = Path.join([workspaces_root, "sym", String.downcase(task["key"])])
    refute File.exists?(workspace_path)

    {_, branch_status} =
      System.cmd("git", [
        "--git-dir",
        remote_path,
        "show-ref",
        "--verify",
        "--quiet",
        "refs/heads/symphonia/task/#{String.downcase(task["key"])}"
      ])

    assert branch_status != 0

    System.put_env("SYMPHONIA_CODEX_APP_SERVER_SKIP_DAEMON", "true")
    System.put_env("SYMPHONIA_CODEX_APP_SERVER_COMMAND", fake_app_server)
    System.delete_env("SYMPHONIA_CODEX_APP_SERVER_STANDALONE_BIN")

    retry = CodingAssistant.start_run(registry_path, repository, task["key"])
    retried_run = wait_for_run(runs_root, retry["run"]["id"], "completed")
    retried_task = wait_for_task_status(repository, task["key"], "in_review")

    assert retried_run["provider"] == "codex_app_server"

    assert retried_task["handoff"]["headBranch"] ==
             "symphonia/task/#{String.downcase(task["key"])}"
  end

  test "client resumes existing app-server threads", %{
    requests_file: requests_file,
    workspaces_root: workspaces_root
  } do
    workspace_path = Path.join(workspaces_root, "direct-resume")
    File.mkdir_p!(workspace_path)

    assert {:ok, output} =
             AppServerClient.run_turn(workspace_path, "Resume this thread.",
               thread_id: "thread-existing"
             )

    assert output["thread_id"] == "thread-existing"
    assert output["turn_id"] == "turn-fake"

    requests = JSON.decode!(File.read!(requests_file))
    assert Enum.any?(requests, &(&1["method"] == "thread/resume"))
    refute Enum.any?(requests, &(&1["method"] == "thread/start"))
  end

  test "client defaults to direct stdio app-server transport", %{
    args_file: args_file,
    fake_app_server: fake_app_server,
    workspaces_root: workspaces_root
  } do
    System.delete_env("SYMPHONIA_CODEX_APP_SERVER_COMMAND")
    System.delete_env("SYMPHONIA_CODEX_APP_SERVER_ARGS")
    System.put_env("SYMPHONIA_CODEX_APP_SERVER_BIN", fake_app_server)

    workspace_path = Path.join(workspaces_root, "direct-stdio-default")
    File.mkdir_p!(workspace_path)

    assert {:ok, output} = AppServerClient.run_turn(workspace_path, "Use default transport.")
    assert output["turn_id"] == "turn-fake"
    assert JSON.decode!(File.read!(args_file)) == ["app-server", "--listen", "stdio://"]
  end

  test "client returns a bounded startup timeout when app-server does not initialize", %{
    workspaces_root: workspaces_root
  } do
    System.put_env("FAKE_APP_SERVER_MODE", "silent_initialize")
    workspace_path = Path.join(workspaces_root, "silent-initialize")
    File.mkdir_p!(workspace_path)

    assert {:error, "Codex App Server did not respond during startup.", []} =
             AppServerClient.run_turn(workspace_path, "Exercise startup timeout.",
               startup_timeout_ms: 250
             )
  end

  test "run metadata is persisted while app-server turn is still active", %{
    registry_path: registry_path,
    repository: repository,
    runs_root: runs_root
  } do
    System.put_env("FAKE_APP_SERVER_MODE", "delayed_complete")

    task =
      TaskStore.create_task(registry_path, repository, %{
        "title" => "Visible progress Codex task",
        "body" => "Create a small app-server output file."
      })

    result = CodingAssistant.start_run(registry_path, repository, task["key"])

    run =
      wait_for_run_matching(runs_root, result["run"]["id"], fn run ->
        run["state"] == "running" and run["current_step"] == "Codex is working" and
          run["codex_thread_id"] == "thread-fake" and run["turn_id"] == "turn-fake"
      end)

    assert run["current_step"] == "Codex is working"

    task = TaskStore.get_task(repository, task["key"])
    assert task["run"]["displayStep"] == "Codex is working"
    refute Map.has_key?(task["run"], "codexThreadId")
    refute Map.has_key?(task["run"], "turnId")
    refute Map.has_key?(task["run"], "workspacePath")

    wait_for_run(runs_root, result["run"]["id"], "completed")
    wait_for_task_status(repository, task["key"], "in_review")
  end

  test "client returns bounded errors for failed, interrupted, and malformed turns", %{
    workspaces_root: workspaces_root
  } do
    cases = [
      {"failed", "Fake turn failure."},
      {"interrupted", "status interrupted"},
      {"malformed_json", ""}
    ]

    for {mode, expected} <- cases do
      System.put_env("FAKE_APP_SERVER_MODE", mode)
      workspace_path = Path.join(workspaces_root, "direct-#{mode}")
      File.mkdir_p!(workspace_path)

      assert {:error, reason, events} =
               AppServerClient.run_turn(workspace_path, "Exercise #{mode}.", timeout_ms: 500)

      assert is_binary(reason)
      assert String.trim(reason) != ""
      assert is_list(events)

      if expected != "" do
        assert reason =~ expected
      end
    end
  end

  test "startup timeout failure is surfaced as the paused task explanation", %{
    registry_path: registry_path,
    repository: repository,
    runs_root: runs_root
  } do
    System.put_env("FAKE_APP_SERVER_MODE", "silent_initialize")
    System.put_env("SYMPHONIA_CODEX_STARTUP_TIMEOUT_MS", "250")

    task =
      TaskStore.create_task(registry_path, repository, %{
        "title" => "Startup timeout task",
        "body" => "Create a small app-server output file."
      })

    result = CodingAssistant.start_run(registry_path, repository, task["key"])
    run = wait_for_run(runs_root, result["run"]["id"], "failed")
    task = wait_for_task_status(repository, task["key"], "paused")

    assert run["error"] == "Codex App Server did not respond during startup."
    assert run["message"] == "Codex App Server did not respond during startup."
    assert run["provider_output"]["app_server_events"] == []
    assert task["pausedReason"] == "run_failed"
    assert task["pausedExplanation"] == "Codex App Server did not respond during startup."
  end

  test "persistent workspace is reused after a failed run retry", %{
    registry_path: registry_path,
    repository: repository,
    runs_root: runs_root
  } do
    [task | _rest] = TaskStore.list_tasks(repository)

    System.put_env("FAKE_APP_SERVER_MODE", "failed")

    first_result =
      CodingAssistant.start_harness_run(registry_path, repository, task["key"], %{
        "eligibility_reason" => "Task is eligible for daemon dispatch."
      })

    failed_run = wait_for_run(runs_root, first_result["run"]["id"], "failed")
    failed_task = wait_for_task_status(repository, task["key"], "paused")

    assert failed_task["pausedReason"] == "run_failed"
    assert failed_run["workspace_path"] =~ Path.join(["sym", "sym-1"])

    System.delete_env("FAKE_APP_SERVER_MODE")
    System.put_env("FAKE_APP_SERVER_OUTPUT_SUFFIX", " retry")

    retry_result =
      CodingAssistant.start_harness_run(registry_path, repository, task["key"], %{
        "eligibility_reason" => "Retry after failure."
      })

    completed_run = wait_for_run(runs_root, retry_result["run"]["id"], "completed")
    wait_for_task_status(repository, task["key"], "in_review")

    assert completed_run["workspace_path"] == failed_run["workspace_path"]

    assert File.read!(Path.join(completed_run["workspace_path"], "app/app-server-output.txt")) =~
             "retry"
  end

  test "app-server provider delegates workspace preparation to the workspace resolver" do
    source =
      Path.expand("../lib/symphonia_service/coding_assistant/app_server_provider.ex", __DIR__)
      |> File.read!()

    assert source =~ "WorkspaceProviders.prepare"
    assert source =~ "WorkspaceProviders.review_context"
    assert source =~ "WorkspaceProviders.release"
    assert source =~ "ChangeApplier.apply"
    refute source =~ "LocalGitWorktreeProvider.prepare"
    refute source =~ "LocalGitWorktreeProvider.release"
    refute source =~ "with_persistent_task_branch_worktree"
  end

  test "completed app-server turn with no committable changes pauses the task", %{
    registry_path: registry_path,
    repository: repository,
    runs_root: runs_root
  } do
    [task | _rest] = TaskStore.list_tasks(repository)
    System.put_env("FAKE_APP_SERVER_MODE", "no_change")

    result =
      CodingAssistant.start_harness_run(registry_path, repository, task["key"], %{
        "eligibility_reason" => "Task is eligible for daemon dispatch."
      })

    run = wait_for_run(runs_root, result["run"]["id"], "failed")
    task = wait_for_task_status(repository, task["key"], "paused")

    assert run["provider_output"]["app_server_events"] != []
    assert run["provider_output"]["change_detection"]["committable"] == []
    assert task["pausedReason"] == "run_failed"

    assert task["pausedExplanation"] ==
             "The Coding Assistant did not produce any files that can be reviewed."
  end

  test "persistent workspace and Codex thread are reused for request-changes continuation", %{
    registry_path: registry_path,
    repository: repository,
    requests_file: requests_file,
    runs_root: runs_root
  } do
    [task | _rest] = TaskStore.list_tasks(repository)

    initial_result =
      CodingAssistant.start_harness_run(registry_path, repository, task["key"], %{
        "eligibility_reason" => "Task is eligible for daemon dispatch."
      })

    initial_run = wait_for_run(runs_root, initial_result["run"]["id"], "completed")
    wait_for_task_status(repository, task["key"], "in_review")

    assert initial_run["codex_thread_id"] == "thread-fake"

    System.put_env("FAKE_APP_SERVER_OUTPUT_SUFFIX", " continuation")

    continuation_result =
      CodingAssistant.continue_from_review_notes(registry_path, repository, task["key"], %{
        "feedback" => "Please update the generated file for continuation coverage."
      })

    continuation_run = wait_for_run(runs_root, continuation_result["run"]["id"], "completed")
    continued_task = wait_for_task_status(repository, task["key"], "in_review")

    assert continuation_run["workspace_path"] == initial_run["workspace_path"]
    assert continuation_run["codex_thread_id"] == initial_run["codex_thread_id"]

    assert File.read!(Path.join(continuation_run["workspace_path"], "app/app-server-output.txt")) =~
             "continuation"

    assert continued_task["body"] =~ "Review notes"

    requests = JSON.decode!(File.read!(requests_file))
    assert Enum.any?(requests, &(&1["method"] == "thread/resume"))
    refute Enum.any?(requests, &(&1["method"] == "thread/start"))
  end

  defp approved_milestone(repository) do
    milestone =
      MilestoneLoop.start(repository, %{"title" => "Codex App Server harness"})["milestone"]

    milestone =
      MilestoneLoop.discuss(repository, milestone["id"], %{
        "title" => "Codex App Server harness",
        "goal" => "Run approved milestone tasks through a persistent Codex App Server workspace.",
        "answers" => %{
          "accomplish" => "Dispatch eligible tasks to Codex App Server.",
          "why" => "Execution should happen through Symphonía.",
          "include" => "Daemon dispatch, app-server provider, summary artifacts.",
          "exclude" => "Opening pull requests automatically.",
          "complete" => "A branch contains code changes and a curated summary.",
          "codebase" => "Harness daemon and provider modules.",
          "risks" => "Raw logs must stay local."
        }
      })["milestone"]

    milestone = MilestoneLoop.requirements(repository, milestone["id"])["milestone"]
    milestone = MilestoneLoop.plan(repository, milestone["id"])["milestone"]
    MilestoneLoop.approve(repository, milestone["id"])["milestone"]
  end

  defp retryable_failed_run!(repository, task, runs_root, retry_offset_seconds) do
    retry_at =
      DateTime.utc_now()
      |> DateTime.add(retry_offset_seconds, :second)
      |> DateTime.to_iso8601()

    run =
      RunStore.create(
        %{
          "provider" => "codex_app_server",
          "repository" => repository["key"],
          "task" => task["key"],
          "kind" => "daemon_assignment",
          "attempt" => 0,
          "max_attempts" => 2
        },
        root: runs_root
      )
      |> RunStore.mark_failed(
        "Codex App Server did not respond during startup.",
        "Transient Codex App Server error. Retry scheduled in 30 seconds.",
        root: runs_root
      )
      |> RunStore.update_metadata(
        %{
          "failure_class" => "transient_provider",
          "retry_at" => retry_at,
          "retry_reason" => "Transient Codex App Server error. Retry scheduled in 30 seconds."
        },
        root: runs_root
      )

    TaskStore.apply_event(repository, task["key"], "fail_run", %{
      "explanation" => run["message"],
      "paused_reason" => "waiting_for_sync"
    })

    TaskStore.patch_task(repository, task["key"], %{
      "frontmatter" => %{"run" => task_run_frontmatter(run)}
    })

    run
  end

  defp rewrite_run!(runs_root, run) do
    path = RunStore.path(run, root: runs_root)
    File.write!(path, JSON.encode!(run))
    run
  end

  defp task_run_frontmatter(run) do
    %{
      "id" => run["id"],
      "kind" => run["kind"],
      "state" => run["state"],
      "current_step" => run["current_step"],
      "message" => run["message"],
      "display_step" => SymphoniaService.CodingAssistant.RunEvents.display_step(run),
      "display_message" => SymphoniaService.CodingAssistant.RunEvents.display_message(run),
      "eligibility_reason" => run["eligibility_reason"],
      "review_branch" => run["review_branch"],
      "curated_summary_path" => run["curated_summary_path"],
      "retry_at" => run["retry_at"],
      "failure_class" => run["failure_class"],
      "attempt" => run["attempt"],
      "max_attempts" => run["max_attempts"],
      "started_at" => run["started_at"],
      "completed_at" => run["completed_at"]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp wait_for_latest_run(runs_root, state, attempts \\ 80) do
    run =
      runs_root
      |> Path.join("run_*.json")
      |> Path.wildcard()
      |> Enum.map(&JSON.decode!(File.read!(&1)))
      |> Enum.max_by(& &1["created_at"], fn -> nil end)

    if run && run["state"] == state do
      run
    else
      if attempts <= 0 do
        flunk("run did not reach #{state}; last state: #{inspect(run && run["state"])}")
      end

      Process.sleep(50)
      wait_for_latest_run(runs_root, state, attempts - 1)
    end
  end

  defp wait_for_run(runs_root, run_id, state, attempts \\ 80) do
    run = RunStore.get(run_id, root: runs_root)

    if run && run["state"] == state do
      run
    else
      if attempts <= 0 do
        flunk("run #{run_id} did not reach #{state}; last state: #{inspect(run && run["state"])}")
      end

      Process.sleep(50)
      wait_for_run(runs_root, run_id, state, attempts - 1)
    end
  end

  defp wait_for_run_matching(runs_root, run_id, predicate, attempts \\ 80) do
    run = RunStore.get(run_id, root: runs_root)

    if run && predicate.(run) do
      run
    else
      if attempts <= 0 do
        flunk("run #{run_id} did not match predicate; last run: #{inspect(run)}")
      end

      Process.sleep(50)
      wait_for_run_matching(runs_root, run_id, predicate, attempts - 1)
    end
  end

  defp commit_workflow_validation!(repo_path, label, command) do
    File.write!(Path.join(repo_path, "WORKFLOW.md"), """
    # WORKFLOW.md

    validation:
      required:
        - label: #{label}
          command: #{command}

    on_run_complete:
      - status: in_review
    """)

    git_output!(["-C", repo_path, "add", "WORKFLOW.md"])

    git_output!([
      "-C",
      repo_path,
      "-c",
      "user.name=Test",
      "-c",
      "user.email=test@example.invalid",
      "commit",
      "-m",
      "Add validation workflow"
    ])

    git_output!(["-C", repo_path, "push", "origin", "main"])
  end

  defp wait_for_task_status(repository, task_key, status, attempts \\ 80) do
    task = TaskStore.get_task(repository, task_key)

    if task && task["status"] == status do
      task
    else
      if attempts <= 0 do
        flunk(
          "task #{task_key} did not reach #{status}; last status: #{inspect(task && task["status"])}"
        )
      end

      Process.sleep(50)
      wait_for_task_status(repository, task_key, status, attempts - 1)
    end
  end

  defp write_fake_app_server!(path) do
    File.write!(path, """
    #!/usr/bin/env node
    const fs = require("fs");
    const readline = require("readline");
    const requestsFile = process.env.FAKE_APP_SERVER_REQUESTS_FILE;
    const argsFile = process.env.FAKE_APP_SERVER_ARGS_FILE;
    const mode = process.env.FAKE_APP_SERVER_MODE || "success";
    const outputSuffix = process.env.FAKE_APP_SERVER_OUTPUT_SUFFIX || "";
    const excludedWrite = process.env.FAKE_APP_SERVER_WRITE_EXCLUDED;
    const requests = [];

    if (argsFile) {
      fs.writeFileSync(argsFile, JSON.stringify(process.argv.slice(2)));
    }

    function save() {
      fs.writeFileSync(requestsFile, JSON.stringify(requests, null, 2));
    }

    function send(message) {
      process.stdout.write(JSON.stringify(message) + "\\n");
    }

    readline.createInterface({ input: process.stdin }).on("line", (line) => {
      const message = JSON.parse(line);
      requests.push(message);
      save();

      if (message.method === "initialize") {
        if (mode === "silent_initialize") {
          return;
        }
        send({ jsonrpc: "2.0", id: message.id, result: { codexHome: "/tmp/codex-home", platformFamily: "unix", platformOs: "macos", userAgent: "fake" } });
      } else if (message.method === "thread/start") {
        send({ jsonrpc: "2.0", id: message.id, result: { thread: { id: "thread-fake" }, cwd: message.params.cwd, approvalPolicy: "never", approvalsReviewer: "auto_review", model: "fake", modelProvider: "fake", sandbox: "workspace-write" } });
      } else if (message.method === "thread/resume") {
        send({ jsonrpc: "2.0", id: message.id, result: { thread: { id: message.params.threadId } } });
      } else if (message.method === "turn/start") {
        const cwd = message.params.cwd;
        const threadId = message.params.threadId || "thread-fake";
        if (mode !== "no_change") {
          fs.mkdirSync(cwd + "/app", { recursive: true });
          fs.writeFileSync(cwd + "/app/app-server-output.txt", "Fake App Server work product" + outputSuffix + "\\n");
          if (excludedWrite) {
            const excludedPath = cwd + "/" + excludedWrite;
            fs.mkdirSync(require("path").dirname(excludedPath), { recursive: true });
            fs.writeFileSync(excludedPath, "Excluded fake App Server output\\n");
          }
        }
        send({ jsonrpc: "2.0", id: message.id, result: { turn: { id: "turn-fake", status: "running" } } });
        if (mode === "malformed_json") {
          process.stdout.write("{malformed-json\\n");
          return;
        }
        send({ jsonrpc: "2.0", method: "agent/message/delta", params: { threadId, turnId: "turn-fake", text: "Fake App Server changed app/app-server-output.txt." } });
        if (mode === "failed") {
          send({ jsonrpc: "2.0", method: "turn/completed", params: { threadId, turn: { id: "turn-fake", status: "failed", error: "Fake turn failure." } } });
        } else if (mode === "interrupted") {
          send({ jsonrpc: "2.0", method: "turn/completed", params: { threadId, turn: { id: "turn-fake", status: "interrupted" } } });
        } else if (mode === "delayed_complete") {
          setTimeout(() => {
            send({ jsonrpc: "2.0", method: "turn/completed", params: { threadId, turn: { id: "turn-fake", status: "completed" } } });
          }, 500);
        } else {
          send({ jsonrpc: "2.0", method: "turn/completed", params: { threadId, turn: { id: "turn-fake", status: "completed" } } });
        }
      }
    });
    """)

    File.chmod(path, 0o700)
  end

  defp setup_git!(root) do
    remote_path = Path.join(root, "remote.git")
    seed_path = Path.join(root, "seed")
    repo_path = Path.join(root, "repo")

    git_output!(["init", "--bare", remote_path])
    File.mkdir_p!(seed_path)
    git_output!(["-C", seed_path, "init"])
    File.write!(Path.join(seed_path, "README.md"), "# Symphonia test repo\n")
    git_output!(["-C", seed_path, "add", "README.md"])

    git_output!([
      "-C",
      seed_path,
      "-c",
      "user.name=Test",
      "-c",
      "user.email=test@example.invalid",
      "commit",
      "-m",
      "Initial commit"
    ])

    git_output!(["-C", seed_path, "branch", "-M", "main"])
    git_output!(["-C", seed_path, "remote", "add", "origin", remote_path])
    git_output!(["-C", seed_path, "push", "origin", "main"])
    git_output!(["--git-dir", remote_path, "symbolic-ref", "HEAD", "refs/heads/main"])
    git_output!(["clone", remote_path, repo_path])

    %{remote_path: remote_path, repo_path: repo_path}
  end

  defp git_output!(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {output, 0} -> output
      {output, _status} -> flunk("git #{Enum.join(args, " ")} failed:\n#{output}")
    end
  end

  defp write_private_key!(path) do
    key = :public_key.generate_key({:rsa, 1024, 65_537})
    entry = :public_key.pem_entry_encode(:RSAPrivateKey, key)
    File.write!(path, :public_key.pem_encode([entry]))
  end

  defp private_repository(repository, registry_path) do
    Map.put(repository, "_registry_path", registry_path)
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
