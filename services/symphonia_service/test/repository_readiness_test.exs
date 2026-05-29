defmodule SymphoniaService.RepositoryReadinessTest do
  use ExUnit.Case

  alias SymphoniaService.CodingAssistant.{ProviderCatalog, RunStore}
  alias SymphoniaService.Harness.{Automation, Daemon}
  alias SymphoniaService.Readiness.{RepositoryReadiness, RepositoryScanner, SetupActions}
  alias SymphoniaService.{RepositoryRegistry, SpecWorkspace, TaskStore, Workspace}

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphonia-repository-readiness-#{System.unique_integer([:positive])}"
      )

    repo_path = Path.join(root, "repo")
    registry_path = Path.join(root, "repositories.json")
    runs_root = Path.join(root, "runs")
    File.mkdir_p!(Path.join(repo_path, ".git"))

    previous_runs_root = System.get_env("SYMPHONIA_RUNS_ROOT")
    previous_skip_daemon = System.get_env("SYMPHONIA_CODEX_APP_SERVER_SKIP_DAEMON")
    System.put_env("SYMPHONIA_RUNS_ROOT", runs_root)
    System.put_env("SYMPHONIA_CODEX_APP_SERVER_SKIP_DAEMON", "true")
    stop_daemon()

    on_exit(fn ->
      stop_daemon()
      restore_env("SYMPHONIA_RUNS_ROOT", previous_runs_root)
      restore_env("SYMPHONIA_CODEX_APP_SERVER_SKIP_DAEMON", previous_skip_daemon)
      File.rm_rf(root)
    end)

    repository = RepositoryRegistry.add(registry_path, %{"path" => repo_path, "key" => "SYM"})

    %{
      root: root,
      repo_path: repo_path,
      registry_path: registry_path,
      repository: repository
    }
  end

  test "reports missing setup passively without starting Harness", %{
    repository: repository,
    registry_path: registry_path
  } do
    readiness = RepositoryReadiness.get(repository, registry_path: registry_path)
    checks = Map.new(readiness["checks"], &{&1["id"], &1})

    assert readiness["state"] == "needs_setup"
    assert checks["workflow_exists"]["status"] == "failed"
    assert checks["workflow_exists"]["action"]["id"] == "create_workflow"
    assert checks["harness_online"]["detail"] == "Harness is offline."
    assert Process.whereis(Daemon) == nil
    assert RunStore.list() == []
  end

  test "reports validation missing as warning and does not mutate tasks", %{
    repository: repository,
    registry_path: registry_path
  } do
    Workspace.initialize(repository)
    Workspace.create_workflow_from_template(repository, "simple-pr")
    task = TaskStore.create_task(registry_path, repository, %{"title" => "Readiness task"})

    readiness = RepositoryReadiness.get(repository, registry_path: registry_path)
    checks = Map.new(readiness["checks"], &{&1["id"], &1})

    assert checks["validation_policy"]["status"] == "warning"
    assert checks["validation_policy"]["detail"] == "No validation command is configured."
    assert TaskStore.get_task(repository, task["key"])["status"] == "todo"
    assert RunStore.list() == []
  end

  test "setup actions create workflow and initialize workspaces explicitly", %{
    repository: repository,
    registry_path: registry_path
  } do
    readiness =
      SetupActions.initialize_workspace(repository, registry_path: registry_path)

    assert Map.new(readiness["checks"], &{&1["id"], &1})["workspace_directories"]["status"] ==
             "passed"

    readiness =
      SetupActions.create_workflow_from_template(repository, %{"template" => "review-first"},
        registry_path: registry_path
      )

    assert Map.new(readiness["checks"], &{&1["id"], &1})["workflow_exists"]["status"] ==
             "passed"

    readiness =
      SetupActions.initialize_spec_workspace(repository, registry_path: registry_path)

    assert Map.new(readiness["checks"], &{&1["id"], &1})["spec_workspace"]["status"] ==
             "passed"
  end

  test "scanner detects project files without executing commands", %{repository: repository} do
    File.write!(Path.join(repository["path"], "package.json"), """
    {
      "dependencies": { "next": "15.0.0", "react": "19.0.0" },
      "scripts": {
        "build": "next build",
        "test:harness-ui": "node --test scripts/harness-ui-model.test.mjs"
      }
    }
    """)

    File.write!(
      Path.join(repository["path"], "mix.exs"),
      "defmodule Fixture.MixProject do\nend\n"
    )

    File.write!(Path.join(repository["path"], "pyproject.toml"), "[tool.pytest.ini_options]\n")
    File.write!(Path.join(repository["path"], "Cargo.toml"), "[package]\nname = \"fixture\"\n")
    File.write!(Path.join(repository["path"], "go.mod"), "module example.invalid/fixture\n")

    scan = RepositoryScanner.scan(repository)

    assert scan["detected"] == ["elixir", "go", "nextjs", "node", "python", "react", "rust"]
    assert scan["files"] == ["Cargo.toml", "go.mod", "mix.exs", "package.json", "pyproject.toml"]
    assert scan["scripts"] == ["build", "test:harness-ui"]

    assert Enum.map(scan["suggestedValidation"], & &1["command"]) == [
             "npm run build",
             "cargo test",
             "mix test",
             "go test ./...",
             "npm run test:harness-ui",
             "pytest"
           ]
  end

  test "provider check-only readiness returns safe reasons without starting Codex" do
    previous_skip_daemon = System.get_env("SYMPHONIA_CODEX_APP_SERVER_SKIP_DAEMON")
    previous_standalone = System.get_env("SYMPHONIA_CODEX_APP_SERVER_STANDALONE_BIN")
    previous_command = System.get_env("SYMPHONIA_CODEX_APP_SERVER_COMMAND")
    previous_bin = System.get_env("SYMPHONIA_CODEX_BIN")
    previous_app_bin = System.get_env("SYMPHONIA_CODEX_APP_SERVER_BIN")

    missing = Path.join(System.tmp_dir!(), "missing-codex-#{System.unique_integer([:positive])}")

    System.delete_env("SYMPHONIA_CODEX_APP_SERVER_SKIP_DAEMON")
    System.delete_env("SYMPHONIA_CODEX_APP_SERVER_COMMAND")
    System.delete_env("SYMPHONIA_CODEX_BIN")
    System.delete_env("SYMPHONIA_CODEX_APP_SERVER_BIN")
    System.put_env("SYMPHONIA_CODEX_APP_SERVER_STANDALONE_BIN", missing)

    try do
      status = ProviderCatalog.readiness_status(mode: :check_only)
      codex = Enum.find(status["providers"], &(&1["id"] == "codex_app_server"))

      assert codex["ready"] == false
      assert codex["binaryAvailable"] == false
      refute codex["reason"] =~ missing
      refute codex["reason"] =~ "SYMPHONIA_CODEX_APP_SERVER_STANDALONE_BIN"
    after
      restore_env("SYMPHONIA_CODEX_APP_SERVER_SKIP_DAEMON", previous_skip_daemon)
      restore_env("SYMPHONIA_CODEX_APP_SERVER_STANDALONE_BIN", previous_standalone)
      restore_env("SYMPHONIA_CODEX_APP_SERVER_COMMAND", previous_command)
      restore_env("SYMPHONIA_CODEX_BIN", previous_bin)
      restore_env("SYMPHONIA_CODEX_APP_SERVER_BIN", previous_app_bin)
    end
  end

  test "ready repository can report ready when Harness is already online", %{
    repository: repository,
    registry_path: registry_path
  } do
    Workspace.initialize(repository)

    File.write!(Path.join(repository["path"], "WORKFLOW.md"), """
    # WORKFLOW.md

    validation:
      required:
        - label: Tests
          command: mix test
    """)

    SpecWorkspace.initialize(repository)

    SpecWorkspace.create_artifact(repository, "milestone", "milestone-001", %{
      "status" => "approved"
    })

    repository =
      RepositoryRegistry.update(registry_path, repository["key"], fn repo ->
        Map.put(repo, "github", %{
          "owner" => "agora-creations",
          "name" => "symphonia",
          "installation_id" => 123,
          "auth_mode" => "app_installation"
        })
      end)

    repository = Automation.enable(registry_path, repository["key"])
    {:ok, _pid} = Daemon.start_link(registry_path: registry_path, timer?: false)

    readiness = RepositoryReadiness.get(repository, registry_path: registry_path)

    assert readiness["state"] == "ready"
  end

  defp stop_daemon do
    try do
      case Process.whereis(Daemon) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end
    catch
      :exit, _ -> :ok
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
