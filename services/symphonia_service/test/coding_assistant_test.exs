defmodule SymphoniaService.CodingAssistantTest do
  use ExUnit.Case

  alias SymphoniaService.{CodingAssistant, RepositoryRegistry, TaskStore, Workspace}
  alias SymphoniaService.GitHub.{InstallationStore, PullRequests}

  defmodule StubClient do
    def create_installation_token(jwt, installation_id) do
      assert String.split(jwt, ".") |> length() == 3
      assert to_string(installation_id) == "123"

      {:ok,
       %{
         "token" => "installation-token",
         "expires_at" =>
           DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
       }}
    end

    def get_branch("installation-token", "agora-creations", "symphonia", "symphonia/task/sym-1") do
      {:ok, %{"name" => "symphonia/task/sym-1"}}
    end

    def create_pull_request("installation-token", "agora-creations", "symphonia", payload) do
      assert payload["head"] == "symphonia/task/sym-1"
      assert payload["base"] == "main"

      {:ok,
       %{
         "number" => 789,
         "html_url" => "https://github.com/agora-creations/symphonia/pull/789",
         "state" => "open",
         "head" => %{"ref" => "symphonia/task/sym-1"},
         "base" => %{"ref" => "main"}
       }}
    end
  end

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphonia-coding-assistant-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    private_key_path = Path.join(root, "github-app.pem")
    write_private_key!(private_key_path)

    %{remote_path: remote_path, repo_path: repo_path} = setup_git!(root)

    registry_path = Path.join(root, "registry.json")
    github_home = Path.join(root, "github")
    runs_root = Path.join(root, "runs")

    previous_app_id = System.get_env("SYMPHONIA_GITHUB_APP_ID")
    previous_private_key = System.get_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH")
    previous_runs_root = System.get_env("SYMPHONIA_RUNS_ROOT")

    System.put_env("SYMPHONIA_GITHUB_APP_ID", "42")
    System.put_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH", private_key_path)
    System.put_env("SYMPHONIA_RUNS_ROOT", runs_root)

    Application.put_env(:symphonia_service, :github_client, StubClient)
    Application.put_env(:symphonia_service, :github_home, github_home)

    on_exit(fn ->
      restore_env("SYMPHONIA_GITHUB_APP_ID", previous_app_id)
      restore_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH", previous_private_key)
      restore_env("SYMPHONIA_RUNS_ROOT", previous_runs_root)
      Application.delete_env(:symphonia_service, :github_client)
      Application.delete_env(:symphonia_service, :github_home)
      File.rm_rf(root)
    end)

    repository = RepositoryRegistry.add(registry_path, %{"path" => repo_path, "key" => "SYM"})
    Workspace.initialize(repository)

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

    task = TaskStore.create_task(registry_path, repository, %{"title" => "Demo assistant task"})

    %{
      registry_path: registry_path,
      repo_path: repo_path,
      remote_path: remote_path,
      repository: RepositoryRegistry.get!(registry_path, "SYM"),
      runs_root: runs_root,
      task: task
    }
  end

  test "local demo assistant creates a run, branch work product, and handoff", %{
    registry_path: registry_path,
    repo_path: repo_path,
    remote_path: remote_path,
    repository: repository,
    runs_root: runs_root,
    task: task
  } do
    result = CodingAssistant.start_run(registry_path, repository, task["key"])

    assert result["run"]["state"] == "completed"
    assert result["task"]["status"] == "in_review"
    assert result["task"]["assistant"] == "local_demo"
    assert result["task"]["run"]["id"] == result["run"]["id"]
    assert result["task"]["handoff"]["headBranch"] == "symphonia/task/sym-1"
    assert result["task"]["handoff"]["baseBranch"] == "main"
    assert result["task"]["handoff"]["filesChanged"] == ["symphonia/demo-output/SYM-1.md"]

    assert [run_file] = Path.wildcard(Path.join(runs_root, "run_*.json"))
    assert File.read!(run_file) =~ "raw_log"

    demo_output =
      git_output!([
        "--git-dir",
        remote_path,
        "show",
        "refs/heads/symphonia/task/sym-1:symphonia/demo-output/SYM-1.md"
      ])

    assert demo_output =~ "Demo Assistant Output"
    assert demo_output =~ "Demo assistant task"

    branch_files =
      git_output!([
        "--git-dir",
        remote_path,
        "ls-tree",
        "-r",
        "--name-only",
        "refs/heads/symphonia/task/sym-1"
      ])

    assert branch_files =~ "symphonia/demo-output/SYM-1.md"
    refute branch_files =~ "symphonia/tasks/SYM-1.md"

    assert git_output!(["-C", repo_path, "branch", "--show-current"]) == "main\n"

    task_markdown = File.read!(Path.join([repo_path, "symphonia", "tasks", "SYM-1.md"]))
    assert task_markdown =~ "status: in_review"
    assert task_markdown =~ "handoff:"
    refute task_markdown =~ "installation-token"
  end

  test "existing approve and open pull request flow works from generated handoff", %{
    registry_path: registry_path,
    repository: repository,
    task: task
  } do
    CodingAssistant.start_run(registry_path, repository, task["key"])
    TaskStore.apply_event(repository, task["key"], "approve")

    updated = PullRequests.open_from_task(repository, task["key"])

    assert updated["githubPrState"] == "open"
    assert updated["githubPr"] == "https://github.com/agora-creations/symphonia/pull/789"
  end

  test "request changes saves review notes and continues from checklist only", %{
    registry_path: registry_path,
    repo_path: repo_path,
    remote_path: remote_path,
    repository: repository,
    runs_root: runs_root,
    task: task
  } do
    CodingAssistant.start_run(registry_path, repository, task["key"])

    feedback =
      "The card is still too dense. Remove validation from the default card, make the project label smaller, and show retry only when paused."

    result =
      CodingAssistant.continue_from_review_notes(registry_path, repository, task["key"], %{
        "feedback" => feedback
      })

    assert result["run"]["state"] == "completed"
    assert result["task"]["status"] == "in_review"
    assert result["review_note"]["original_feedback"] == feedback

    assert result["review_note"]["requested_changes"] == [
             "Make task cards less dense.",
             "Remove validation from the default card.",
             "Make the project label visually smaller.",
             "Show the retry action only when the task is paused."
           ]

    task_markdown = File.read!(Path.join([repo_path, "symphonia", "tasks", "SYM-1.md"]))
    assert task_markdown =~ "## Review notes"
    assert task_markdown =~ "## Handoff history"
    assert task_markdown =~ "Original feedback:\n#{feedback}"
    assert task_markdown =~ "- [ ] Make task cards less dense."
    assert task_markdown =~ "review_continuation:"

    continuation_run =
      runs_root
      |> Path.join("run_*.json")
      |> Path.wildcard()
      |> Enum.map(&JSON.decode!(File.read!(&1)))
      |> Enum.find(&(&1["kind"] == "review_continuation"))

    assert continuation_run["state"] == "completed"
    assert continuation_run["attempt"] == 1
    assert continuation_run["input"] =~ "Requested changes:"
    assert continuation_run["input"] =~ "- Make task cards less dense."
    refute continuation_run["input"] =~ "The card is still too dense"
    assert continuation_run["raw_log"]

    demo_output =
      git_output!([
        "--git-dir",
        remote_path,
        "show",
        "refs/heads/symphonia/task/sym-1:symphonia/demo-output/SYM-1.md"
      ])

    assert demo_output =~ "## Continuation input"
    assert demo_output =~ "Requested changes:"
    assert demo_output =~ "- Show the retry action only when the task is paused."
    refute demo_output =~ "The card is still too dense"

    branch_files =
      git_output!([
        "--git-dir",
        remote_path,
        "ls-tree",
        "-r",
        "--name-only",
        "refs/heads/symphonia/task/sym-1"
      ])

    assert branch_files =~ "symphonia/demo-output/SYM-1.md"
    refute branch_files =~ "symphonia/tasks/SYM-1.md"
  end

  test "continuation retry limit is scoped to the current review cycle", %{
    registry_path: registry_path,
    repo_path: repo_path,
    repository: repository,
    runs_root: runs_root,
    task: task
  } do
    CodingAssistant.start_run(registry_path, repository, task["key"])

    first_result =
      CodingAssistant.continue_from_review_notes(registry_path, repository, task["key"], %{
        "feedback" => "Remove validation from the default card.",
        "forceFailureOnce" => true
      })

    assert first_result["task"]["status"] == "in_review"

    first_markdown = File.read!(Path.join([repo_path, "symphonia", "tasks", "SYM-1.md"]))
    assert first_markdown =~ "attempt: 2"
    assert first_markdown =~ first_result["review_note"]["id"]

    second_result =
      CodingAssistant.continue_from_review_notes(registry_path, repository, task["key"], %{
        "feedback" => "Make the project label smaller."
      })

    assert second_result["task"]["status"] == "in_review"

    second_markdown = File.read!(Path.join([repo_path, "symphonia", "tasks", "SYM-1.md"]))
    assert second_markdown =~ "attempt: 1"
    assert second_markdown =~ second_result["review_note"]["id"]
    refute second_result["review_note"]["id"] == first_result["review_note"]["id"]

    continuation_runs =
      runs_root
      |> Path.join("run_*.json")
      |> Path.wildcard()
      |> Enum.map(&JSON.decode!(File.read!(&1)))
      |> Enum.filter(&(&1["kind"] == "review_continuation"))

    assert Enum.count(continuation_runs) == 3
  end

  test "failed local demo run pauses the task with run failed", %{
    registry_path: registry_path,
    repository: repository,
    task: task
  } do
    result =
      CodingAssistant.start_run(registry_path, repository, task["key"], %{"forceFailure" => true})

    assert result["run"]["state"] == "failed"
    assert result["task"]["status"] == "paused"
    assert result["task"]["pausedReason"] == "run_failed"
  end

  test "two failed continuation attempts pause the task with run failed", %{
    registry_path: registry_path,
    repo_path: repo_path,
    repository: repository,
    runs_root: runs_root,
    task: task
  } do
    CodingAssistant.start_run(registry_path, repository, task["key"])

    result =
      CodingAssistant.continue_from_review_notes(registry_path, repository, task["key"], %{
        "feedback" => "Remove validation from the default card.",
        "forceFailure" => true
      })

    assert result["run"]["state"] == "failed"
    assert result["task"]["status"] == "paused"
    assert result["task"]["pausedReason"] == "run_failed"
    assert result["task"]["pausedExplanation"] ==
             "The Coding Assistant could not produce a new handoff after your requested changes."

    task_markdown = File.read!(Path.join([repo_path, "symphonia", "tasks", "SYM-1.md"]))
    assert task_markdown =~ "attempt: 2"
    assert task_markdown =~ "paused_reason: run_failed"

    continuation_runs =
      runs_root
      |> Path.join("run_*.json")
      |> Path.wildcard()
      |> Enum.map(&JSON.decode!(File.read!(&1)))
      |> Enum.filter(&(&1["kind"] == "review_continuation"))

    assert Enum.count(continuation_runs) == 2
    assert Enum.all?(continuation_runs, &(&1["state"] == "failed"))
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
