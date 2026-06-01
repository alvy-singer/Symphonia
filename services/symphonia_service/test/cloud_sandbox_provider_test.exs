defmodule SymphoniaService.CloudSandboxProviderTest do
  use ExUnit.Case

  alias SymphoniaService.Access.AuditLog
  alias SymphoniaService.CodingAssistant.RunStore
  alias SymphoniaService.GitHub.InstallationStore
  alias SymphoniaService.Runners.AssignmentStore
  alias SymphoniaService.Secrets.ReferenceStore, as: SecretReferences
  alias SymphoniaService.Sandbox.OpenSandboxOperations
  alias SymphoniaService.Sandbox.OpenSandboxSmoke
  alias SymphoniaService.Sandbox.Policy, as: SandboxPolicy
  alias SymphoniaService.Sandbox.Registry, as: SandboxRegistry
  alias SymphoniaService.Sandbox.SourceBundle

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

  defmodule MockOpenSandboxClient do
    def create(_config, body) do
      notify({:opensandbox_create, body})

      case failure() do
        "create" -> {:error, "opensandbox_request_failed"}
        _other -> {:ok, %{"id" => "sandbox_mock", "status" => %{"state" => "Running"}}}
      end
    end

    def get(_config, sandbox_id) do
      notify({:opensandbox_get, sandbox_id})
      {:ok, %{"id" => sandbox_id, "status" => %{"state" => "Running"}}}
    end

    def endpoint(_config, sandbox_id, port) do
      notify({:opensandbox_endpoint, sandbox_id, port})

      case failure() do
        "endpoint" ->
          {:error, "opensandbox_request_failed"}

        _other ->
          {:ok,
           %{
             "url" => "http://execd.example.invalid",
             "headers" => %{"X-EXECD-ACCESS-TOKEN" => "exec-token"}
           }}
      end
    end

    def upload_file(execd, path, content) do
      notify({:opensandbox_upload, path, byte_size(content), execd})

      case failure() do
        "upload" -> {:error, "opensandbox_request_failed"}
        _other -> :ok
      end
    end

    def run_command(_execd, command, opts) do
      notify({:opensandbox_command, command, opts})

      if failure() == "run" and String.contains?(command, "python3") do
        {:error, "opensandbox_request_failed"}
      else
        {:ok, "completed"}
      end
    end

    def download_file(_execd, path) do
      notify({:opensandbox_download, path})

      case failure() do
        "result" ->
          {:ok, "not-json"}

        _other ->
          {diff, changed_files, summary} =
            if Application.get_env(:symphonia_service, :opensandbox_result_provider) ==
                 "gemini_cli" do
              {
                gemini_diff(),
                [%{"path" => "lib/gemini_output.ex", "status" => "added"}],
                "Gemini CLI produced a reviewable patch."
              }
            else
              {
                opensandbox_diff(),
                [%{"path" => "lib/opensandbox_output.ex", "status" => "added"}],
                "OpenSandbox produced a reviewable patch."
              }
            end

          {:ok,
           JSON.encode!(%{
             "status" => "completed",
             "patchBundle" => %{
               "format" => "git_diff",
               "encoding" => "utf8",
               "diff" => diff
             },
             "changedFiles" => changed_files,
             "publicSummary" => summary
           })}
      end
    end

    def delete(_config, sandbox_id) do
      notify({:opensandbox_delete, sandbox_id})

      case failure() do
        "release" -> {:error, "opensandbox_request_failed"}
        _other -> :ok
      end
    end

    defp opensandbox_diff do
      """
      diff --git a/lib/opensandbox_output.ex b/lib/opensandbox_output.ex
      new file mode 100644
      index 0000000..1269488
      --- /dev/null
      +++ b/lib/opensandbox_output.ex
      @@ -0,0 +1,2 @@
      +defmodule OpenSandboxOutput do
      +end
      """
      |> String.trim_leading()
    end

    defp gemini_diff do
      """
      diff --git a/lib/gemini_output.ex b/lib/gemini_output.ex
      new file mode 100644
      index 0000000..1269488
      --- /dev/null
      +++ b/lib/gemini_output.ex
      @@ -0,0 +1,2 @@
      +defmodule GeminiOutput do
      +end
      """
      |> String.trim_leading()
    end

    defp notify(message) do
      if pid = Application.get_env(:symphonia_service, :opensandbox_test_pid) do
        send(pid, message)
      end

      :ok
    end

    defp failure, do: Application.get_env(:symphonia_service, :opensandbox_failure)
  end

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphonia-cloud-sandbox-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)

    private_key_path = Path.join(root, "github-app.pem")
    write_private_key!(private_key_path)

    %{remote_path: remote_path, repo_path: repo_path} = setup_git!(root)

    registry_path = Path.join(root, "repositories.json")
    runs_root = Path.join(root, "runs")
    workspaces_root = Path.join(root, "workspaces")
    sandboxes_root = Path.join(root, "sandboxes")
    github_home = Path.join(root, "github")

    previous_app_id = System.get_env("SYMPHONIA_GITHUB_APP_ID")
    previous_private_key = System.get_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH")
    previous_runs_root = System.get_env("SYMPHONIA_RUNS_ROOT")
    previous_workspaces_root = System.get_env("SYMPHONIA_WORKSPACES_ROOT")
    previous_sandboxes_root = System.get_env("SYMPHONIA_SANDBOXES_ROOT")
    previous_opensandbox_endpoint = System.get_env("SYMPHONIA_OPENSANDBOX_ENDPOINT")
    previous_opensandbox_api_key = System.get_env("SYMPHONIA_OPENSANDBOX_API_KEY")
    previous_gemini_api_key = System.get_env("GEMINI_API_KEY")

    System.put_env("SYMPHONIA_GITHUB_APP_ID", "42")
    System.put_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH", private_key_path)
    System.put_env("SYMPHONIA_RUNS_ROOT", runs_root)
    System.put_env("SYMPHONIA_WORKSPACES_ROOT", workspaces_root)
    System.put_env("SYMPHONIA_SANDBOXES_ROOT", sandboxes_root)

    Application.put_env(:symphonia_service, :github_client, StubClient)
    Application.put_env(:symphonia_service, :github_home, github_home)

    on_exit(fn ->
      restore_env("SYMPHONIA_GITHUB_APP_ID", previous_app_id)
      restore_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH", previous_private_key)
      restore_env("SYMPHONIA_RUNS_ROOT", previous_runs_root)
      restore_env("SYMPHONIA_WORKSPACES_ROOT", previous_workspaces_root)
      restore_env("SYMPHONIA_SANDBOXES_ROOT", previous_sandboxes_root)
      restore_env("SYMPHONIA_OPENSANDBOX_ENDPOINT", previous_opensandbox_endpoint)
      restore_env("SYMPHONIA_OPENSANDBOX_API_KEY", previous_opensandbox_api_key)
      restore_env("GEMINI_API_KEY", previous_gemini_api_key)
      Application.delete_env(:symphonia_service, :github_client)
      Application.delete_env(:symphonia_service, :github_home)
      Application.delete_env(:symphonia_service, :opensandbox_client)
      Application.delete_env(:symphonia_service, :opensandbox_test_pid)
      Application.delete_env(:symphonia_service, :opensandbox_failure)
      Application.delete_env(:symphonia_service, :opensandbox_result_provider)
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

    %{
      root: root,
      registry_path: registry_path,
      remote_path: remote_path,
      repository: repository
    }
  end

  test "manual cloud sandbox run imports through the patch importer and releases", %{
    root: root,
    registry_path: registry_path,
    remote_path: remote_path
  } do
    repository = enable_sandbox(registry_path)
    task = create_task(registry_path, repository, "Cloud sandbox success")
    events_path = Path.join(root, "sandbox-events.jsonl")

    result =
      start_sandbox_run(registry_path, repository, task, %{
        "fakeSandboxEventsPath" => events_path
      })

    completed_task = wait_for_task(repository, task["key"], "in_review")
    assignment = AssignmentStore.get(registry_path, result["assignment"]["id"])

    assert assignment["state"] == "completed"
    assert completed_task["run"]["executionMode"] == "cloud_sandbox"
    assert completed_task["run"]["workspaceProvider"] == "cloud_sandbox"
    assert completed_task["handoff"]["summary"] == "Sandbox produced a reviewable patch."
    assert "lib/cloud_sandbox_output.ex" in completed_task["handoff"]["filesChanged"]

    branch_files =
      git_output!([
        "--git-dir",
        remote_path,
        "ls-tree",
        "-r",
        "--name-only",
        "refs/heads/symphonia/task/#{String.downcase(task["key"])}"
      ])

    assert branch_files =~ "lib/cloud_sandbox_output.ex"
    refute branch_files =~ completed_task["handoff"]["curatedSummaryPath"]

    summary =
      PrivateWorkspace.read_artifact(
        Map.put(repository, "_registry_path", registry_path),
        "run_summary",
        completed_task["handoff"]["curatedSummaryId"]
      )

    assert summary["body"] =~ "Sandbox produced a reviewable patch."

    events = wait_for_event_steps(events_path, ["create", "prepare", "run", "release"])
    assert Enum.map(events, & &1["step"]) == ["create", "prepare", "run", "release"]

    run = RunStore.get(result["run"]["id"])
    public_run = JSON.encode!(RunStore.public(run))
    refute Regex.match?(~r/sandbox_\d/, public_run)
    refute public_run =~ "diff --git"

    actions = audit_actions(registry_path)
    assert "sandbox.run_selected" in actions
    assert "sandbox.create_started" in actions
    assert "sandbox.prepare_completed" in actions
    assert "sandbox.result_received" in actions
    assert "sandbox.release_completed" in actions
  end

  test "opensandbox readiness is passive and uses environment-backed secret references", %{
    registry_path: registry_path,
    repository: repository
  } do
    missing =
      SandboxRegistry.readiness(
        Map.put(repository, "sandboxProvider", "opensandbox"),
        registry_path
      )

    refute missing["ready"]
    assert missing["reason"] == "opensandbox_endpoint_missing"

    System.put_env("SYMPHONIA_OPENSANDBOX_ENDPOINT", "http://opensandbox.example.invalid")
    System.put_env("SYMPHONIA_OPENSANDBOX_API_KEY", "opensandbox-secret-value")

    {:ok, reference} =
      SecretReferences.create(registry_path, repository, %{
        "label" => "OpenSandbox API key",
        "scope" => "sandbox.provider",
        "source" => "environment",
        "envName" => "SYMPHONIA_OPENSANDBOX_API_KEY"
      })

    ready =
      SandboxRegistry.readiness(
        Map.put(repository, "sandboxProvider", "opensandbox"),
        registry_path
      )

    assert ready["ready"]
    assert ready["provider"] == "opensandbox"
    assert ready["credential"] == "environment_reference_configured"
    refute JSON.encode!(ready) =~ "opensandbox-secret-value"
    refute JSON.encode!(ready) =~ reference["envName"]
  end

  test "opensandbox cloud sandbox run uses source bundle and imports locally", %{
    registry_path: registry_path,
    remote_path: remote_path
  } do
    Application.put_env(:symphonia_service, :opensandbox_client, MockOpenSandboxClient)
    Application.put_env(:symphonia_service, :opensandbox_test_pid, self())
    System.put_env("SYMPHONIA_OPENSANDBOX_ENDPOINT", "http://opensandbox.example.invalid")
    System.put_env("SYMPHONIA_OPENSANDBOX_API_KEY", "opensandbox-secret-value")

    repository = enable_opensandbox(registry_path)
    task = create_task(registry_path, repository, "OpenSandbox success")

    result = start_sandbox_run(registry_path, repository, task, %{})

    completed_task = wait_for_task(repository, task["key"], "in_review")
    assignment = AssignmentStore.get(registry_path, result["assignment"]["id"])

    assert assignment["state"] == "completed"
    assert completed_task["handoff"]["summary"] == "OpenSandbox produced a reviewable patch."
    assert "lib/opensandbox_output.ex" in completed_task["handoff"]["filesChanged"]

    branch_files =
      git_output!([
        "--git-dir",
        remote_path,
        "ls-tree",
        "-r",
        "--name-only",
        "refs/heads/symphonia/task/#{String.downcase(task["key"])}"
      ])

    assert branch_files =~ "lib/opensandbox_output.ex"

    assert_received {:opensandbox_create, create_body}
    assert create_body["image"]["uri"] == "opensandbox/code-interpreter:v1.0.2"
    assert create_body["timeout"] == 1_800
    assert create_body["resourceLimits"] == %{"cpu" => "2", "memory" => "4Gi"}

    assert_received {:opensandbox_endpoint, "sandbox_mock", 44_772}
    assert_received {:opensandbox_upload, "/workspace/source.tar", source_size, _execd}
    assert source_size > 0

    assert_received {:opensandbox_upload, "/workspace/.symphonia/context-pack.json",
                     _context_size, _execd}

    assert_received {:opensandbox_command, prepare_command, _prepare_opts}
    assert prepare_command =~ "git commit --allow-empty -m symphonia-baseline"
    assert_received {:opensandbox_command, runner_command, _runner_opts}
    assert runner_command =~ "symphonia-sandbox-runner"
    assert_received {:opensandbox_download, "/workspace/.symphonia/result.json"}
    assert_received {:opensandbox_delete, "sandbox_mock"}

    run = RunStore.get(result["run"]["id"])
    encoded = JSON.encode!(RunStore.public(run))
    refute encoded =~ "sandbox_mock"
    refute encoded =~ "exec-token"
    refute encoded =~ "opensandbox-secret-value"
    refute encoded =~ "diff --git"

    audit = JSON.encode!(AuditLog.list(registry_path, repository, limit: :all))
    refute audit =~ "sandbox_mock"
    refute audit =~ "exec-token"
    refute audit =~ "opensandbox-secret-value"
    refute audit =~ "diff --git"

    actions = audit_actions(registry_path)
    assert "sandbox.prepare_started" in actions
    assert "sandbox.run_started" in actions
    assert "sandbox.release_completed" in actions
  end

  test "gemini cli manual run is opensandbox-only and imports through patch importer", %{
    registry_path: registry_path,
    remote_path: remote_path
  } do
    Application.put_env(:symphonia_service, :opensandbox_client, MockOpenSandboxClient)
    Application.put_env(:symphonia_service, :opensandbox_test_pid, self())
    Application.put_env(:symphonia_service, :opensandbox_result_provider, "gemini_cli")
    System.put_env("SYMPHONIA_OPENSANDBOX_ENDPOINT", "http://opensandbox.example.invalid")
    System.put_env("SYMPHONIA_OPENSANDBOX_API_KEY", "opensandbox-secret-value")
    System.put_env("GEMINI_API_KEY", "gemini-secret-value")

    repository = enable_gemini_opensandbox(registry_path)
    task = create_task(registry_path, repository, "Gemini sandbox success")

    result =
      start_sandbox_run(registry_path, repository, task, %{
        "providerId" => "gemini_cli"
      })

    completed_task = wait_for_task(repository, task["key"], "in_review")
    assignment = AssignmentStore.get(registry_path, result["assignment"]["id"])

    assert assignment["state"] == "completed"
    assert assignment["provider"] == "gemini_cli"
    assert assignment["context_pack"]["provider"] == "gemini_cli"
    assert assignment["context_pack"]["renderedPrompt"] =~ "OpenSandbox source-bundle workspace"
    refute assignment["context_pack"]["renderedPrompt"] =~ "Existing Codex thread ID"

    assert completed_task["run"]["provider"] == "gemini_cli"
    assert completed_task["run"]["executionMode"] == "cloud_sandbox"
    assert completed_task["handoff"]["summary"] == "Gemini CLI produced a reviewable patch."
    assert "lib/gemini_output.ex" in completed_task["handoff"]["filesChanged"]

    branch_files =
      git_output!([
        "--git-dir",
        remote_path,
        "ls-tree",
        "-r",
        "--name-only",
        "refs/heads/symphonia/task/#{String.downcase(task["key"])}"
      ])

    assert branch_files =~ "lib/gemini_output.ex"

    assert_received {:opensandbox_upload, "/workspace/.symphonia/provider-context.json",
                     _context_size, _execd}

    assert_received {:opensandbox_upload, "/workspace/.symphonia/bin/symphonia-provider-runner",
                     _script_size, _execd}

    assert_received {:opensandbox_upload, "/workspace/.symphonia/provider-env.json", _env_size,
                     _execd}

    runner_command =
      received_commands()
      |> Enum.find(&String.contains?(&1, "symphonia-provider-runner --provider gemini_cli"))

    assert is_binary(runner_command)
    assert runner_command =~ "symphonia-provider-runner --provider gemini_cli"
    refute runner_command =~ "gemini-secret-value"
    assert_received {:opensandbox_delete, "sandbox_mock"}

    run = RunStore.get(result["run"]["id"])
    public_run = JSON.encode!(RunStore.public(run))
    refute public_run =~ "gemini-secret-value"
    refute public_run =~ assignment["context_pack"]["renderedPrompt"]
    refute public_run =~ "diff --git"

    task_payload = JSON.encode!(completed_task)
    refute task_payload =~ "gemini-secret-value"
    refute task_payload =~ assignment["context_pack"]["renderedPrompt"]

    audit = JSON.encode!(AuditLog.list(registry_path, repository, limit: :all))
    assert audit =~ "provider.gemini_cli_run_selected"
    assert audit =~ "provider.gemini_cli_result_received"
    refute audit =~ "gemini-secret-value"
    refute audit =~ assignment["context_pack"]["renderedPrompt"]
    refute audit =~ "diff --git"
  end

  test "gemini cli run rejects local mode and missing provider allowlist", %{
    registry_path: registry_path,
    repository: repository
  } do
    task = create_task(registry_path, repository, "Gemini rejected")

    assert_raise ArgumentError, "Gemini CLI runs require cloud_sandbox execution in V1.", fn ->
      CodingAssistant.start_run(registry_path, repository, task["key"], %{
        "providerId" => "gemini_cli",
        "actor" => %{"id" => "maintainer", "name" => "Maintainer", "role" => "maintainer"}
      })
    end

    System.put_env("SYMPHONIA_OPENSANDBOX_ENDPOINT", "http://opensandbox.example.invalid")
    System.put_env("SYMPHONIA_OPENSANDBOX_API_KEY", "opensandbox-secret-value")
    System.put_env("GEMINI_API_KEY", "gemini-secret-value")

    repository = enable_opensandbox(registry_path)
    task = create_task(registry_path, repository, "Gemini not allowlisted")

    assert_raise ArgumentError, "Gemini CLI is not allowed for this repository.", fn ->
      start_sandbox_run(registry_path, repository, task, %{"providerId" => "gemini_cli"})
    end

    audit = JSON.encode!(AuditLog.list(registry_path, repository, limit: :all))
    assert audit =~ "provider.gemini_cli_run_denied"
    assert audit =~ "provider_not_allowed"
    refute audit =~ "gemini-secret-value"
  end

  test "opensandbox source bundle excludes private runtime material", %{
    root: root,
    repository: repository
  } do
    repo_path = repository["path"]
    File.mkdir_p!(Path.join(repo_path, ".symphonia/runs"))
    File.mkdir_p!(Path.join(repo_path, "audit"))
    File.mkdir_p!(Path.join(repo_path, "provider-output"))
    File.mkdir_p!(Path.join(repo_path, "terminal-logs"))
    File.mkdir_p!(Path.join(repo_path, "validation-logs"))
    File.mkdir_p!(Path.join(repo_path, "node_modules/pkg"))
    File.mkdir_p!(Path.join(repo_path, "lib"))
    File.write!(Path.join(repo_path, ".env"), "SECRET=value\n")
    File.write!(Path.join(repo_path, ".symphonia/runs/run.json"), "{}\n")
    File.write!(Path.join(repo_path, "audit/events.jsonl"), "{}\n")
    File.write!(Path.join(repo_path, "provider-output/output.log"), "raw\n")
    File.write!(Path.join(repo_path, "terminal-logs/terminal.log"), "raw\n")
    File.write!(Path.join(repo_path, "validation-logs/validation.log"), "raw\n")
    File.write!(Path.join(repo_path, "node_modules/pkg/index.js"), "module.exports = {}\n")
    File.write!(Path.join(repo_path, "lib/reviewable.ex"), "defmodule Reviewable do\nend\n")
    git_output!(["-C", repo_path, "add", "-A"])

    git_output!([
      "-C",
      repo_path,
      "-c",
      "user.name=Test",
      "-c",
      "user.email=test@example.invalid",
      "commit",
      "-m",
      "Add bundle fixture"
    ])

    base_sha = String.trim(git_output!(["-C", repo_path, "rev-parse", "HEAD"]))
    {:ok, archive} = SourceBundle.archive(repository, %{"base_sha" => base_sha})
    archive_path = Path.join(root, "source.tar")
    File.write!(archive_path, archive)
    {listing, 0} = System.cmd("tar", ["-tf", archive_path], stderr_to_stdout: true)

    assert listing =~ "lib/reviewable.ex"
    refute listing =~ ".git"
    refute listing =~ ".env"
    refute listing =~ ".symphonia/runs"
    refute listing =~ "audit/events.jsonl"
    refute listing =~ "provider-output"
    refute listing =~ "terminal-logs"
    refute listing =~ "validation-logs"
    refute listing =~ "node_modules"
  end

  test "opensandbox smoke action uses fixture workspace and records sanitized operations", %{
    registry_path: registry_path,
    repository: _repository
  } do
    Application.put_env(:symphonia_service, :opensandbox_client, MockOpenSandboxClient)
    Application.put_env(:symphonia_service, :opensandbox_test_pid, self())
    System.put_env("SYMPHONIA_OPENSANDBOX_ENDPOINT", "http://opensandbox.example.invalid")
    System.put_env("SYMPHONIA_OPENSANDBOX_API_KEY", "opensandbox-secret-value")

    repository = enable_opensandbox(registry_path)
    before_tasks = TaskStore.list_tasks(repository)

    assert {:ok, smoke} =
             OpenSandboxSmoke.run(registry_path, repository, %{
               "id" => "owner",
               "name" => "Owner",
               "role" => "owner"
             })

    assert smoke["status"] == "passed"
    assert smoke["changedFileCount"] == 1
    assert smoke["workspaceMode"] == "source_bundle"
    assert TaskStore.list_tasks(repository) == before_tasks

    assert_received {:opensandbox_create, _create_body}
    assert_received {:opensandbox_upload, "/workspace/source.tar", source_size, _execd}
    assert source_size > 0

    assert_received {:opensandbox_upload, "/workspace/.symphonia/context-pack.json",
                     _context_size, _execd}

    assert_received {:opensandbox_command, prepare_command, _prepare_opts}
    assert prepare_command =~ "git commit --allow-empty -m symphonia-baseline"
    assert_received {:opensandbox_command, smoke_command, _smoke_opts}
    assert smoke_command =~ "python3"
    assert_received {:opensandbox_download, "/workspace/.symphonia/result.json"}
    assert_received {:opensandbox_delete, "sandbox_mock"}

    operations = OpenSandboxOperations.public(registry_path, repository)
    assert operations["lastSmokeStatus"] == "passed"
    refute operations["cleanupWarning"]

    audit = JSON.encode!(AuditLog.list(registry_path, repository, limit: :all))
    assert audit =~ "sandbox.opensandbox_smoke_started"
    assert audit =~ "sandbox.opensandbox_smoke_completed"
    refute audit =~ "sandbox_mock"
    refute audit =~ "exec-token"
    refute audit =~ "opensandbox-secret-value"
    refute audit =~ "diff --git"
  end

  test "opensandbox smoke release failure is a safe cleanup warning", %{
    registry_path: registry_path,
    repository: _repository
  } do
    Application.put_env(:symphonia_service, :opensandbox_client, MockOpenSandboxClient)
    Application.put_env(:symphonia_service, :opensandbox_test_pid, self())
    Application.put_env(:symphonia_service, :opensandbox_failure, "release")
    System.put_env("SYMPHONIA_OPENSANDBOX_ENDPOINT", "http://opensandbox.example.invalid")
    System.put_env("SYMPHONIA_OPENSANDBOX_API_KEY", "opensandbox-secret-value")

    repository = enable_opensandbox(registry_path)

    assert {:ok, smoke} =
             OpenSandboxSmoke.run(registry_path, repository, %{
               "id" => "owner",
               "name" => "Owner",
               "role" => "owner"
             })

    assert smoke["status"] == "passed"
    assert smoke["cleanupWarning"]

    operations = OpenSandboxOperations.public(registry_path, repository)
    assert operations["lastSmokeStatus"] == "passed"
    assert operations["cleanupWarning"]
    assert operations["lastCleanupStatus"] == "warning"

    audit = JSON.encode!(AuditLog.list(registry_path, repository, limit: :all))
    assert audit =~ "sandbox.opensandbox_smoke_completed"
    refute audit =~ "sandbox_mock"
    refute audit =~ "opensandbox-secret-value"
  end

  test "opensandbox smoke run failure attempts release and records safe failure", %{
    registry_path: registry_path,
    repository: _repository
  } do
    Application.put_env(:symphonia_service, :opensandbox_client, MockOpenSandboxClient)
    Application.put_env(:symphonia_service, :opensandbox_test_pid, self())
    Application.put_env(:symphonia_service, :opensandbox_failure, "run")
    System.put_env("SYMPHONIA_OPENSANDBOX_ENDPOINT", "http://opensandbox.example.invalid")
    System.put_env("SYMPHONIA_OPENSANDBOX_API_KEY", "opensandbox-secret-value")

    repository = enable_opensandbox(registry_path)

    assert {:error, {409, payload}} =
             OpenSandboxSmoke.run(registry_path, repository, %{
               "id" => "owner",
               "name" => "Owner",
               "role" => "owner"
             })

    assert payload["status"] == "failed"
    assert payload["reasonCode"] in ["sandbox_unreachable", "sandbox_run_failed"]
    assert_received {:opensandbox_delete, "sandbox_mock"}

    operations = OpenSandboxOperations.public(registry_path, repository)
    assert operations["lastSmokeStatus"] == "failed"
    refute operations["cleanupWarning"]

    audit = JSON.encode!(AuditLog.list(registry_path, repository, limit: :all))
    assert audit =~ "sandbox.opensandbox_smoke_failed"
    refute audit =~ "sandbox_mock"
    refute audit =~ "exec-token"
    refute audit =~ "opensandbox-secret-value"
  end

  test "opensandbox policy rejects unconfigured provider before sandbox creation", %{
    registry_path: registry_path
  } do
    SandboxPolicy.set(registry_path, "SYM", %{
      "sandboxExecutionAllowed" => true,
      "sandboxProvider" => "opensandbox"
    })

    repository =
      SymphoniaService.Runners.RepositoryPolicy.update_policy(registry_path, "SYM", %{
        "allowedSandboxProviders" => ["opensandbox"]
      })

    task = create_task(registry_path, repository, "OpenSandbox missing config")
    actor = %{"id" => "maintainer", "name" => "Maintainer", "role" => "maintainer"}

    assert {:error, {409, %{"reasonCode" => "opensandbox_endpoint_missing"}}} =
             SandboxPolicy.authorize_run(registry_path, repository, actor, task, %{
               "executionMode" => "cloud_sandbox",
               "allowSandboxExecution" => true
             })
  end

  test "release failure is a cleanup warning and does not block review", %{
    registry_path: registry_path,
    repository: _repository
  } do
    repository = enable_sandbox(registry_path)
    task = create_task(registry_path, repository, "Cloud sandbox cleanup warning")

    result =
      start_sandbox_run(registry_path, repository, task, %{
        "fakeSandboxFailure" => "release"
      })

    completed_task = wait_for_task(repository, task["key"], "in_review")
    assignment = AssignmentStore.get(registry_path, result["assignment"]["id"])

    assert assignment["state"] == "completed"
    assert completed_task["run"]["cleanupWarning"]["code"] == "sandbox_release_failed"

    assert completed_task["run"]["cleanupWarning"]["message"] ==
             "Sandbox cleanup needs attention."

    actions = audit_actions(registry_path)
    assert "sandbox.release_failed" in actions

    encoded = JSON.encode!(completed_task["run"])
    refute Regex.match?(~r/sandbox_\d/, encoded)
    refute encoded =~ "diff --git"
  end

  test "release is attempted after prepare failure", %{
    root: root,
    registry_path: registry_path
  } do
    repository = enable_sandbox(registry_path)
    task = create_task(registry_path, repository, "Cloud sandbox prepare failure")
    events_path = Path.join(root, "sandbox-prepare-failure.jsonl")

    result =
      start_sandbox_run(registry_path, repository, task, %{
        "fakeSandboxFailure" => "prepare",
        "fakeSandboxEventsPath" => events_path
      })

    failed_task = wait_for_task(repository, task["key"], "paused")
    assignment = AssignmentStore.get(registry_path, result["assignment"]["id"])

    assert assignment["state"] == "failed"
    assert failed_task["pausedReason"] == "run_failed"
    events = wait_for_event_steps(events_path, ["create", "release"])
    assert Enum.map(events, & &1["step"]) == ["create", "release"]
  end

  test "release is attempted after run and import failures", %{
    root: root,
    registry_path: registry_path
  } do
    repository = enable_sandbox(registry_path)

    run_failure_task = create_task(registry_path, repository, "Cloud sandbox run failure")
    run_failure_events = Path.join(root, "sandbox-run-failure.jsonl")

    run_failure =
      start_sandbox_run(registry_path, repository, run_failure_task, %{
        "fakeSandboxFailure" => "run",
        "fakeSandboxEventsPath" => run_failure_events
      })

    wait_for_task(repository, run_failure_task["key"], "paused")

    assert AssignmentStore.get(registry_path, run_failure["assignment"]["id"])["state"] ==
             "failed"

    assert Enum.map(
             wait_for_event_steps(run_failure_events, ["create", "prepare", "release"]),
             & &1["step"]
           ) ==
             ["create", "prepare", "release"]

    import_failure_task = create_task(registry_path, repository, "Cloud sandbox import failure")
    import_failure_events = Path.join(root, "sandbox-import-failure.jsonl")

    import_failure =
      start_sandbox_run(registry_path, repository, import_failure_task, %{
        "fakePatchPath" => "symphonia/tasks/SYM-1.md",
        "fakeSandboxEventsPath" => import_failure_events
      })

    wait_for_task(repository, import_failure_task["key"], "paused")

    assert AssignmentStore.get(registry_path, import_failure["assignment"]["id"])["state"] ==
             "failed"

    events = wait_for_event_steps(import_failure_events, ["create", "prepare", "run", "release"])
    assert Enum.map(events, & &1["step"]) == ["create", "prepare", "run", "release"]
  end

  test "sandbox policy is default off and requires explicit run flag", %{
    registry_path: registry_path,
    repository: repository
  } do
    task = create_task(registry_path, repository, "Cloud sandbox policy")
    actor = %{"id" => "maintainer", "name" => "Maintainer", "role" => "maintainer"}

    refute SandboxPolicy.public(repository)["sandboxExecutionAllowed"]

    assert {:error, {403, %{"reasonCode" => "sandbox_execution_disabled"}}} =
             SandboxPolicy.authorize_run(registry_path, repository, actor, task, %{
               "executionMode" => "cloud_sandbox"
             })
  end

  defp enable_sandbox(registry_path) do
    SandboxPolicy.set(registry_path, "SYM", %{
      "sandboxExecutionAllowed" => true,
      "sandboxProvider" => "fake_sandbox"
    })

    SymphoniaService.Runners.RepositoryPolicy.update_policy(registry_path, "SYM", %{
      "allowedSandboxProviders" => ["fake_sandbox"]
    })
  end

  defp enable_opensandbox(registry_path) do
    repository = RepositoryRegistry.get!(registry_path, "SYM")

    {:ok, _reference} =
      SecretReferences.create(registry_path, repository, %{
        "label" => "OpenSandbox API key",
        "scope" => "sandbox.provider",
        "source" => "environment",
        "envName" => "SYMPHONIA_OPENSANDBOX_API_KEY"
      })

    SandboxPolicy.set(registry_path, "SYM", %{
      "sandboxExecutionAllowed" => true,
      "sandboxProvider" => "opensandbox"
    })

    SymphoniaService.Runners.RepositoryPolicy.update_policy(registry_path, "SYM", %{
      "allowedSandboxProviders" => ["opensandbox"]
    })
  end

  defp enable_gemini_opensandbox(registry_path) do
    repository = enable_opensandbox(registry_path)

    {:ok, _reference} =
      SecretReferences.create(registry_path, repository, %{
        "label" => "Gemini API key",
        "scope" => "provider.gemini_cli",
        "source" => "environment",
        "envName" => "GEMINI_API_KEY"
      })

    SymphoniaService.Runners.RepositoryPolicy.update_policy(registry_path, "SYM", %{
      "allowedSandboxProviders" => ["opensandbox"],
      "allowedCodingAssistantProviders" => ["codex_app_server", "gemini_cli"]
    })
  end

  defp create_task(registry_path, repository, title) do
    TaskStore.create_task(registry_path, repository, %{
      "title" => title,
      "body" => "Create a sandbox fixture file."
    })
  end

  defp start_sandbox_run(registry_path, repository, task, params) do
    CodingAssistant.start_run(
      registry_path,
      repository,
      task["key"],
      Map.merge(
        %{
          "executionMode" => "cloud_sandbox",
          "allowSandboxExecution" => true,
          "actor" => %{"id" => "maintainer", "name" => "Maintainer", "role" => "maintainer"}
        },
        params
      )
    )
  end

  defp wait_for_task(repository, task_key, status, attempts \\ 100)

  defp wait_for_task(repository, task_key, status, attempts) when attempts > 0 do
    task = TaskStore.get_task(repository, task_key)

    if task["status"] == status do
      task
    else
      Process.sleep(50)
      wait_for_task(repository, task_key, status, attempts - 1)
    end
  end

  defp wait_for_task(repository, task_key, status, 0) do
    flunk(
      "task #{task_key} did not reach #{status}: #{inspect(TaskStore.get_task(repository, task_key))}"
    )
  end

  defp sandbox_events(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&JSON.decode!/1)
  end

  defp wait_for_event_steps(path, expected_steps, attempts \\ 100)

  defp wait_for_event_steps(path, expected_steps, attempts) when attempts > 0 do
    events = if File.exists?(path), do: sandbox_events(path), else: []
    steps = Enum.map(events, & &1["step"])

    if steps == expected_steps do
      events
    else
      Process.sleep(50)
      wait_for_event_steps(path, expected_steps, attempts - 1)
    end
  end

  defp wait_for_event_steps(path, expected_steps, 0) do
    events = if File.exists?(path), do: sandbox_events(path), else: []
    flunk("sandbox events did not reach #{inspect(expected_steps)}: #{inspect(events)}")
  end

  defp received_commands(commands \\ []) do
    receive do
      {:opensandbox_command, command, _opts} -> received_commands([command | commands])
    after
      0 -> Enum.reverse(commands)
    end
  end

  defp audit_actions(registry_path) do
    registry_path
    |> AuditLog.list(%{"key" => "SYM"}, limit: :all)
    |> Enum.map(& &1["action"])
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

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
