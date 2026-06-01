defmodule SymphoniaService.RemoteRunnerExecutionTest do
  use ExUnit.Case

  alias SymphoniaService.CodingAssistant.RunStore
  alias SymphoniaService.GitHub.InstallationStore

  alias SymphoniaService.Runners.{
    Assignments,
    AssignmentStore,
    FakeRunner,
    PatchBundle,
    Registry,
    SelectionPolicy
  }

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
        "symphonia-remote-runner-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)

    private_key_path = Path.join(root, "github-app.pem")
    write_private_key!(private_key_path)

    %{remote_path: remote_path, repo_path: repo_path} = setup_git!(root)

    registry_path = Path.join(root, "repositories.json")
    runs_root = Path.join(root, "runs")
    workspaces_root = Path.join(root, "workspaces")
    github_home = Path.join(root, "github")

    previous_app_id = System.get_env("SYMPHONIA_GITHUB_APP_ID")
    previous_private_key = System.get_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH")
    previous_runs_root = System.get_env("SYMPHONIA_RUNS_ROOT")
    previous_workspaces_root = System.get_env("SYMPHONIA_WORKSPACES_ROOT")

    System.put_env("SYMPHONIA_GITHUB_APP_ID", "42")
    System.put_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH", private_key_path)
    System.put_env("SYMPHONIA_RUNS_ROOT", runs_root)
    System.put_env("SYMPHONIA_WORKSPACES_ROOT", workspaces_root)

    Application.put_env(:symphonia_service, :github_client, StubClient)
    Application.put_env(:symphonia_service, :github_home, github_home)

    on_exit(fn ->
      restore_env("SYMPHONIA_GITHUB_APP_ID", previous_app_id)
      restore_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH", previous_private_key)
      restore_env("SYMPHONIA_RUNS_ROOT", previous_runs_root)
      restore_env("SYMPHONIA_WORKSPACES_ROOT", previous_workspaces_root)
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
        repo
        |> Map.put("remoteExecutionAllowed", true)
        |> Map.put("github", %{
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

    task =
      TaskStore.create_task(registry_path, repository, %{
        "title" => "Remote runner task",
        "body" => "Create a small remote runner file."
      })

    {runner, runner_token} =
      FakeRunner.register!(
        registry_path,
        %{"role" => "owner", "name" => "Owner"},
        %{
          "capabilities" => %{
            "codexAppServer" => true,
            "localGitWorktree" => false,
            "experimentalSandbox" => true,
            "validation" => true
          }
        }
      )

    repository =
      RepositoryRegistry.update(registry_path, "SYM", fn repo ->
        Map.put(repo, "allowedRunnerIds", [runner["id"]])
      end)

    %{
      registry_path: registry_path,
      remote_path: remote_path,
      repository: repository,
      runner: Registry.public(runner),
      runner_token: runner_token,
      task: task
    }
  end

  test "trusted runner claims an assignment and imports an idempotent patch result", %{
    registry_path: registry_path,
    remote_path: remote_path,
    repository: repository,
    runner: runner,
    runner_token: runner_token,
    task: task
  } do
    actor = %{"id" => "maintainer", "name" => "Maintainer", "role" => "maintainer"}

    {:ok, selected} =
      SelectionPolicy.select_for_run(registry_path, repository, actor,
        runner_id: runner["id"],
        allow_remote_execution: true,
        remote_execution: true
      )

    result =
      CodingAssistant.start_run(registry_path, repository, task["key"], %{
        "runner" => selected,
        "actor" => actor
      })

    assignment_id = result["assignment"]["id"]
    assignment = AssignmentStore.get(registry_path, assignment_id)

    assert assignment["state"] == "queued"
    refute JSON.encode!(AssignmentStore.runner_payload(assignment)) =~ repository["path"]
    refute JSON.encode!(AssignmentStore.runner_payload(assignment)) =~ "installation-token"

    assert {:ok, claimed} = Assignments.claim(registry_path, runner["id"], runner_token)
    assert claimed["id"] == assignment_id
    assert claimed["state"] == "claimed"

    assert {:ok, running} =
             Assignments.record_event(
               registry_path,
               runner["id"],
               assignment_id,
               runner_token,
               %{"step" => "running_provider", "message" => "Running on runner"}
             )

    assert running["state"] == "running"

    result_payload = patch_result(assignment)

    assert {:ok, completed, :imported} =
             Assignments.submit_result(
               registry_path,
               runner["id"],
               assignment_id,
               runner_token,
               result_payload
             )

    assert completed["state"] == "completed"

    assert {:ok, ^completed, :idempotent} =
             Assignments.submit_result(
               registry_path,
               runner["id"],
               assignment_id,
               runner_token,
               result_payload
             )

    completed_task = TaskStore.get_task(repository, task["key"])
    assert completed_task["status"] == "in_review"
    assert completed_task["handoff"]["summary"] == "Remote runner produced a reviewable patch."
    assert "lib/remote_runner_output.ex" in completed_task["handoff"]["filesChanged"]
    assert completed_task["run"]["executionMode"] == "remote"
    assert completed_task["run"]["runner"]["id"] == runner["id"]

    branch_files =
      git_output!([
        "--git-dir",
        remote_path,
        "ls-tree",
        "-r",
        "--name-only",
        "refs/heads/symphonia/task/sym-1"
      ])

    assert branch_files =~ "lib/remote_runner_output.ex"
    refute branch_files =~ completed_task["handoff"]["curatedSummaryPath"]

    summary =
      PrivateWorkspace.read_artifact(
        Map.put(repository, "_registry_path", registry_path),
        "run_summary",
        completed_task["handoff"]["curatedSummaryId"]
      )

    assert summary["body"] =~ "Remote runner produced a reviewable patch."

    run = RunStore.get(result["run"]["id"])
    refute JSON.encode!(RunStore.public(run)) =~ "diff --git"
  end

  test "result idempotency and canceled assignments reject unsafe repeats", %{
    registry_path: registry_path,
    repository: repository,
    runner: runner,
    runner_token: runner_token,
    task: task
  } do
    actor = %{"id" => "maintainer", "name" => "Maintainer", "role" => "maintainer"}

    {:ok, selected} =
      SelectionPolicy.select_for_run(registry_path, repository, actor,
        runner_id: runner["id"],
        allow_remote_execution: true,
        remote_execution: true
      )

    result =
      CodingAssistant.start_run(registry_path, repository, task["key"], %{
        "runner" => selected,
        "actor" => actor
      })

    assignment = AssignmentStore.get(registry_path, result["assignment"]["id"])

    Assignments.cancel_run(
      registry_path,
      repository,
      task["key"],
      RunStore.get(result["run"]["id"])
    )

    assert {:error, "assignment_canceled"} =
             Assignments.submit_result(
               registry_path,
               runner["id"],
               assignment["id"],
               runner_token,
               patch_result(assignment)
             )
  end

  test "patch safety rejects protected paths and digest mismatches", %{
    registry_path: registry_path
  } do
    assignment = %{
      "id" => "assignment_safety",
      "run_id" => "run_safety",
      "runner_id" => "runner_safety",
      "base_sha" => "base"
    }

    protected = result_with_diff(assignment, "symphonia/tasks/SYM-1.md", "changed\n")
    assert {:error, "protected_path_rejected"} = PatchBundle.validate(protected, assignment)

    mismatch =
      assignment
      |> result_with_diff("lib/safe.ex", "safe\n")
      |> put_in(["patchBundle", "sha256"], String.duplicate("0", 64))

    assert {:error, "patch_digest_mismatch"} = PatchBundle.validate(mismatch, assignment)

    traversal = result_with_diff(assignment, "../secret.txt", "secret\n")
    assert {:error, "path_traversal_rejected"} = PatchBundle.validate(traversal, assignment)

    _ = registry_path
  end

  defp patch_result(assignment) do
    result_with_diff(
      assignment,
      "lib/remote_runner_output.ex",
      "defmodule RemoteRunnerOutput do\nend\n"
    )
    |> Map.put("publicSummary", "Remote runner produced a reviewable patch.")
  end

  defp result_with_diff(assignment, path, body) do
    added_lines =
      body
      |> String.split("\n", trim: false)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map_join("\n", &"+#{&1}")

    line_count = body |> String.split("\n", trim: true) |> length()

    diff =
      """
      diff --git a/#{path} b/#{path}
      new file mode 100644
      index 0000000..1269488
      --- /dev/null
      +++ b/#{path}
      @@ -0,0 +1,#{line_count} @@
      #{added_lines}
      """
      |> String.trim_leading()

    %{
      "assignmentId" => assignment["id"],
      "runId" => assignment["run_id"],
      "runnerId" => assignment["runner_id"],
      "status" => "completed",
      "baseSha" => assignment["base_sha"],
      "headSha" => "remote-head",
      "patchBundle" => %{
        "format" => "git_diff",
        "encoding" => "utf8",
        "sha256" => PatchBundle.sha256(diff),
        "diff" => diff
      },
      "changedFiles" => [%{"path" => path, "status" => "added"}],
      "changedFilesDigest" => PatchBundle.changed_files_digest([path]),
      "publicTimeline" => [
        %{
          "step" => "running_provider",
          "message" => "Runner completed the Coding Assistant turn."
        }
      ]
    }
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
