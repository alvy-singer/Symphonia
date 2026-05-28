defmodule SymphoniaService.CodingAssistantTest do
  use ExUnit.Case

  alias SymphoniaService.{CodingAssistant, RepositoryRegistry, TaskStore, Workspace}
  alias SymphoniaService.CodingAssistant.RunStore
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

  defmodule SlowProvider do
    @behaviour SymphoniaService.CodingAssistant.Provider

    def id, do: "slow_demo"

    def run(_repository, _task, run, _params) do
      if pid = Application.get_env(:symphonia_service, :slow_provider_test_pid) do
        send(pid, {:slow_provider_started, run["id"]})
      end

      Process.sleep(:infinity)
      {:error, "The Coding Assistant should have been canceled."}
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
    previous_provider = Application.get_env(:symphonia_service, :coding_assistant_provider)

    System.put_env("SYMPHONIA_GITHUB_APP_ID", "42")
    System.put_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH", private_key_path)
    System.put_env("SYMPHONIA_RUNS_ROOT", runs_root)

    Application.put_env(:symphonia_service, :github_client, StubClient)
    Application.put_env(:symphonia_service, :github_home, github_home)

    Application.put_env(
      :symphonia_service,
      :coding_assistant_provider,
      SymphoniaService.CodingAssistant.LocalDemoProvider
    )

    on_exit(fn ->
      restore_env("SYMPHONIA_GITHUB_APP_ID", previous_app_id)
      restore_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH", previous_private_key)
      restore_env("SYMPHONIA_RUNS_ROOT", previous_runs_root)
      Application.delete_env(:symphonia_service, :github_client)
      Application.delete_env(:symphonia_service, :github_home)
      Application.delete_env(:symphonia_service, :slow_provider_test_pid)
      restore_app_env(:coding_assistant_provider, previous_provider)
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

    assert result["run"]["state"] in ["queued", "running"]
    assert result["task"]["status"] == "in_progress"

    result = wait_for_run(repository, task["key"], result["run"]["id"], "completed")

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
    result = CodingAssistant.start_run(registry_path, repository, task["key"])
    wait_for_run(repository, task["key"], result["run"]["id"], "completed")
    approved = TaskStore.apply_event(repository, task["key"], "approve")

    assert approved["reviewApproved"] == true
    refute approved["githubPr"]
    refute approved["githubPrState"] == "open"

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
    initial = CodingAssistant.start_run(registry_path, repository, task["key"])
    wait_for_run(repository, task["key"], initial["run"]["id"], "completed")

    feedback =
      "The card is still too dense. Remove validation from the default card, make the project label smaller, and show retry only when paused."

    result =
      CodingAssistant.continue_from_review_notes(registry_path, repository, task["key"], %{
        "feedback" => feedback
      })

    assert result["run"]["state"] in ["queued", "running"]
    result_task = wait_for_task_status(repository, task["key"], "in_review")
    assert result_task["status"] == "in_review"
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
    initial = CodingAssistant.start_run(registry_path, repository, task["key"])
    wait_for_run(repository, task["key"], initial["run"]["id"], "completed")

    first_result =
      CodingAssistant.continue_from_review_notes(registry_path, repository, task["key"], %{
        "feedback" => "Remove validation from the default card.",
        "forceFailureOnce" => true
      })

    wait_for_task_status(repository, task["key"], "in_review")

    first_markdown = File.read!(Path.join([repo_path, "symphonia", "tasks", "SYM-1.md"]))
    assert first_markdown =~ "attempt: 2"
    assert first_markdown =~ first_result["review_note"]["id"]

    second_result =
      CodingAssistant.continue_from_review_notes(registry_path, repository, task["key"], %{
        "feedback" => "Make the project label smaller."
      })

    wait_for_task_status(repository, task["key"], "in_review")

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

    result = wait_for_run(repository, task["key"], result["run"]["id"], "failed")

    assert result["run"]["state"] == "failed"
    assert result["task"]["status"] == "paused"
    assert result["task"]["pausedReason"] == "run_failed"
  end

  test "active run can be canceled and leaves task paused for retry", %{
    registry_path: registry_path,
    repository: repository,
    task: task
  } do
    Application.put_env(:symphonia_service, :coding_assistant_provider, SlowProvider)
    Application.put_env(:symphonia_service, :slow_provider_test_pid, self())

    result = CodingAssistant.start_run(registry_path, repository, task["key"])

    assert result["run"]["state"] in ["queued", "running"]
    assert result["task"]["status"] == "in_progress"
    assert_receive {:slow_provider_started, run_id}, 1_000

    canceled = CodingAssistant.cancel_run(repository, task["key"], run_id)

    assert canceled["run"]["state"] == "canceled"
    assert canceled["task"]["status"] == "paused"
    assert canceled["task"]["pausedReason"] == "waiting_for_user"

    assert canceled["task"]["pausedExplanation"] ==
             "Run canceled. The task is paused. You can retry when ready."

    assert RunStore.get(run_id)["state"] == "canceled"

    Application.put_env(
      :symphonia_service,
      :coding_assistant_provider,
      SymphoniaService.CodingAssistant.LocalDemoProvider
    )

    retry = CodingAssistant.start_run(registry_path, repository, task["key"])
    retry = wait_for_run(repository, task["key"], retry["run"]["id"], "completed")

    assert retry["task"]["status"] == "in_review"
  end

  test "HTTP run detail and cancel endpoints expose active background run", %{
    registry_path: registry_path,
    repository: repository,
    task: task
  } do
    Application.put_env(:symphonia_service, :coding_assistant_provider, SlowProvider)
    Application.put_env(:symphonia_service, :slow_provider_test_pid, self())

    port = free_port()
    name = :"symphonia_http_test_#{System.unique_integer([:positive])}"

    {:ok, _server} =
      SymphoniaService.HTTPServer.start_link(port: port, registry_path: registry_path, name: name)

    {201, started} =
      http_json(
        :post,
        "http://127.0.0.1:#{port}/api/repositories/#{repository["key"]}/tasks/#{task["key"]}/coding-assistant/runs",
        %{}
      )

    run_id = started["run"]["id"]
    assert started["run"]["state"] in ["queued", "running"]
    assert started["task"]["status"] == "in_progress"
    assert_receive {:slow_provider_started, ^run_id}, 1_000

    {200, detail} =
      http_json(
        :get,
        "http://127.0.0.1:#{port}/api/repositories/#{repository["key"]}/tasks/#{task["key"]}/coding-assistant/runs/#{run_id}"
      )

    assert detail["run"]["state"] == "running"
    assert detail["run"]["currentStep"] == "Running Coding Assistant"
    assert detail["run"]["displayStep"] == "Starting Codex"
    refute Map.has_key?(detail["run"], "workspacePath")
    refute Map.has_key?(detail["run"], "codexThreadId")
    refute Map.has_key?(detail["run"], "turnId")

    {200, progress} =
      http_json(
        :get,
        "http://127.0.0.1:#{port}/api/repositories/#{repository["key"]}/tasks/#{task["key"]}/runs/#{run_id}/events"
      )

    assert [%{"id" => first_event_id, "event" => "run-progress"} | _rest] = progress["events"]
    assert Enum.all?(progress["events"], &Map.has_key?(&1, "displayStep"))
    refute JSON.encode!(progress["events"]) =~ "workspacePath"
    refute JSON.encode!(progress["events"]) =~ "codexThreadId"
    refute JSON.encode!(progress["events"]) =~ "turnId"

    {200, replayed_progress} =
      http_json(
        :get,
        "http://127.0.0.1:#{port}/api/repositories/#{repository["key"]}/tasks/#{task["key"]}/runs/#{run_id}/events?after=#{URI.encode(first_event_id)}"
      )

    refute Enum.any?(replayed_progress["events"], &(&1["id"] == first_event_id))

    {200, harness_status} =
      http_json(:get, "http://127.0.0.1:#{port}/api/harness/status")

    assert harness_status["harness"]["mode"] == "local_service"
    assert harness_status["harness"]["limits"]["maxConcurrentRuns"] == 1

    {200, canceled} =
      http_json(
        :post,
        "http://127.0.0.1:#{port}/api/repositories/#{repository["key"]}/tasks/#{task["key"]}/coding-assistant/runs/#{run_id}/cancel",
        %{}
      )

    assert canceled["run"]["state"] == "canceled"
    assert canceled["task"]["status"] == "paused"
    assert canceled["task"]["pausedReason"] == "waiting_for_user"
  end

  test "recovering interrupted active runs pauses affected tasks", %{
    registry_path: registry_path,
    repository: repository,
    runs_root: runs_root,
    task: task
  } do
    run =
      RunStore.create(
        %{
          "provider" => "local_demo",
          "repository" => repository["key"],
          "task" => task["key"]
        },
        root: runs_root
      )
      |> RunStore.mark_running(root: runs_root)

    TaskStore.apply_event(repository, task["key"], "start")

    TaskStore.patch_task(repository, task["key"], %{
      "frontmatter" => %{
        "run" => %{
          "id" => run["id"],
          "state" => run["state"],
          "current_step" => run["current_step"],
          "started_at" => run["started_at"]
        }
      }
    })

    CodingAssistant.recover_interrupted_runs(registry_path, root: runs_root)

    recovered = RunStore.get(run["id"], root: runs_root)
    recovered_task = TaskStore.get_task(repository, task["key"])

    assert recovered["state"] == "failed"

    assert recovered["message"] ==
             "The Coding Assistant stopped because Symphonía restarted during the run."

    assert recovered_task["status"] == "paused"
    assert recovered_task["pausedReason"] == "run_failed"

    assert recovered_task["pausedExplanation"] ==
             "The Coding Assistant stopped because Symphonía restarted during the run."
  end

  test "two failed continuation attempts pause the task with run failed", %{
    registry_path: registry_path,
    repo_path: repo_path,
    repository: repository,
    runs_root: runs_root,
    task: task
  } do
    initial = CodingAssistant.start_run(registry_path, repository, task["key"])
    wait_for_run(repository, task["key"], initial["run"]["id"], "completed")

    result =
      CodingAssistant.continue_from_review_notes(registry_path, repository, task["key"], %{
        "feedback" => "Remove validation from the default card.",
        "forceFailure" => true
      })

    assert result["run"]["state"] in ["queued", "running"]
    result_task = wait_for_task_status(repository, task["key"], "paused")
    final_run = latest_run!(runs_root, "review_continuation")

    assert final_run["state"] == "failed"
    assert result_task["status"] == "paused"
    assert result_task["pausedReason"] == "run_failed"

    assert result_task["pausedExplanation"] ==
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

  defp wait_for_run(repository, task_key, run_id, state, attempts \\ 80) do
    run = RunStore.get(run_id)
    task = TaskStore.get_task(repository, task_key)

    if run && run["state"] == state do
      %{"run" => RunStore.public(run), "task" => task}
    else
      if attempts <= 0 do
        flunk("run #{run_id} did not reach #{state}; last state: #{inspect(run && run["state"])}")
      end

      Process.sleep(50)
      wait_for_run(repository, task_key, run_id, state, attempts - 1)
    end
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

  defp latest_run!(runs_root, kind) do
    runs_root
    |> Path.join("run_*.json")
    |> Path.wildcard()
    |> Enum.map(&JSON.decode!(File.read!(&1)))
    |> Enum.filter(&(&1["kind"] == kind))
    |> Enum.max_by(& &1["created_at"])
  end

  defp http_json(:get, url) do
    :inets.start()

    {:ok, {{_version, status, _reason}, _headers, body}} =
      :httpc.request(:get, {String.to_charlist(url), []}, [], body_format: :binary)

    {status, JSON.decode!(body)}
  end

  defp http_json(:post, url, payload) do
    :inets.start()

    {:ok, {{_version, status, _reason}, _headers, body}} =
      :httpc.request(
        :post,
        {String.to_charlist(url), [], ~c"application/json", JSON.encode!(payload)},
        [],
        body_format: :binary
      )

    {status, JSON.decode!(body)}
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false])
    {:ok, {_address, port}} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    port
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

  defp restore_app_env(key, nil), do: Application.delete_env(:symphonia_service, key)
  defp restore_app_env(key, value), do: Application.put_env(:symphonia_service, key, value)
end
