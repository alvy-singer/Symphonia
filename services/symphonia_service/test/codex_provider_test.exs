defmodule SymphoniaService.CodexProviderTest do
  use ExUnit.Case

  alias SymphoniaService.{CodingAssistant, RepositoryRegistry, TaskStore, Workspace}
  alias SymphoniaService.CodingAssistant.CodexProvider
  alias SymphoniaService.CodingAssistant.RunStore
  alias SymphoniaService.GitHub.InstallationStore

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
        "symphonia-codex-provider-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    private_key_path = Path.join(root, "github-app.pem")
    write_private_key!(private_key_path)

    %{remote_path: remote_path, repo_path: repo_path} = setup_git!(root)

    registry_path = Path.join(root, "registry.json")
    github_home = Path.join(root, "github")
    runs_root = Path.join(root, "runs")
    fake_codex = Path.join(root, "fake-codex")
    args_file = Path.join(root, "codex-args.txt")
    prompt_file = Path.join(root, "codex-prompt.txt")

    write_fake_codex!(fake_codex)

    previous_app_id = System.get_env("SYMPHONIA_GITHUB_APP_ID")
    previous_private_key = System.get_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH")
    previous_runs_root = System.get_env("SYMPHONIA_RUNS_ROOT")
    previous_codex_bin = System.get_env("SYMPHONIA_CODEX_BIN")
    previous_codex_mode = System.get_env("FAKE_CODEX_MODE")
    previous_args_file = System.get_env("FAKE_CODEX_ARGS_FILE")
    previous_prompt_file = System.get_env("FAKE_CODEX_PROMPT_FILE")
    previous_provider = Application.get_env(:symphonia_service, :coding_assistant_provider)

    System.put_env("SYMPHONIA_GITHUB_APP_ID", "42")
    System.put_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH", private_key_path)
    System.put_env("SYMPHONIA_RUNS_ROOT", runs_root)
    System.put_env("SYMPHONIA_CODEX_BIN", fake_codex)
    System.put_env("FAKE_CODEX_ARGS_FILE", args_file)
    System.put_env("FAKE_CODEX_PROMPT_FILE", prompt_file)

    Application.put_env(:symphonia_service, :github_client, StubClient)
    Application.put_env(:symphonia_service, :github_home, github_home)
    Application.put_env(:symphonia_service, :coding_assistant_provider, CodexProvider)

    on_exit(fn ->
      restore_env("SYMPHONIA_GITHUB_APP_ID", previous_app_id)
      restore_env("SYMPHONIA_GITHUB_APP_PRIVATE_KEY_PATH", previous_private_key)
      restore_env("SYMPHONIA_RUNS_ROOT", previous_runs_root)
      restore_env("SYMPHONIA_CODEX_BIN", previous_codex_bin)
      restore_env("FAKE_CODEX_MODE", previous_codex_mode)
      restore_env("FAKE_CODEX_ARGS_FILE", previous_args_file)
      restore_env("FAKE_CODEX_PROMPT_FILE", previous_prompt_file)
      Application.delete_env(:symphonia_service, :github_client)
      Application.delete_env(:symphonia_service, :github_home)
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

    task =
      TaskStore.create_task(registry_path, repository, %{
        "title" => "Implement Codex output",
        "body" => "# Implement Codex output\n\nCreate a small output file."
      })

    %{
      args_file: args_file,
      prompt_file: prompt_file,
      registry_path: registry_path,
      remote_path: remote_path,
      repo_path: repo_path,
      repository: RepositoryRegistry.get!(registry_path, "SYM"),
      runs_root: runs_root,
      task: task
    }
  end

  test "codex provider invokes CLI safely and commits detected work product", %{
    args_file: args_file,
    prompt_file: prompt_file,
    registry_path: registry_path,
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
    assert result["task"]["assistant"] == "codex"
    assert result["task"]["handoff"]["filesChanged"] == ["app/codex-output.txt"]
    assert result["task"]["handoff"]["summary"] == "Fake Codex changed app/codex-output.txt."

    args = File.read!(args_file)
    assert args =~ "exec\n"
    assert args =~ "--json\n"
    assert args =~ "--sandbox\nworkspace-write\n"
    assert args =~ "--ask-for-approval\nnever\n"
    assert args =~ "-\n"

    prompt = File.read!(prompt_file)
    assert prompt =~ "Task key: SYM-1"
    assert prompt =~ "Create a small output file."

    output =
      git_output!([
        "--git-dir",
        remote_path,
        "show",
        "refs/heads/symphonia/task/sym-1:app/codex-output.txt"
      ])

    assert output =~ "Fake Codex work product"

    branch_files =
      git_output!([
        "--git-dir",
        remote_path,
        "ls-tree",
        "-r",
        "--name-only",
        "refs/heads/symphonia/task/sym-1"
      ])

    assert branch_files =~ "app/codex-output.txt"
    refute branch_files =~ "symphonia/tasks/SYM-1.md"

    run_json = read_single_run!(runs_root)
    assert run_json["provider"] == "codex"
    assert run_json["provider_output"]["argv"] |> Enum.join(" ") =~ "--ask-for-approval never"
    assert run_json["provider_output"]["jsonl"] =~ "\"event\":\"done\""
    assert run_json["raw_log"]

    task_markdown = File.read!(Path.join([repository["path"], "symphonia", "tasks", "SYM-1.md"]))
    refute task_markdown =~ "\"event\":\"done\""
    refute task_markdown =~ "installation-token"
  end

  test "missing codex binary pauses task with a plain error", %{
    registry_path: registry_path,
    repository: repository,
    task: task
  } do
    System.put_env("SYMPHONIA_CODEX_BIN", "/tmp/not-a-real-codex-binary")

    result = CodingAssistant.start_run(registry_path, repository, task["key"])

    result = wait_for_run(repository, task["key"], result["run"]["id"], "failed")

    assert result["run"]["state"] == "failed"
    assert result["task"]["status"] == "paused"
    assert result["task"]["pausedReason"] == "run_failed"

    assert result["task"]["pausedExplanation"] ==
             "The Coding Assistant can't start because Codex is not available on this computer."
  end

  test "codex failure pauses task and keeps raw output local", %{
    registry_path: registry_path,
    repository: repository,
    runs_root: runs_root,
    task: task
  } do
    System.put_env("FAKE_CODEX_MODE", "fail")

    result = CodingAssistant.start_run(registry_path, repository, task["key"])

    result = wait_for_run(repository, task["key"], result["run"]["id"], "failed")

    assert result["run"]["state"] == "failed"
    assert result["task"]["status"] == "paused"
    assert result["task"]["pausedReason"] == "run_failed"

    run_json = read_single_run!(runs_root)
    assert run_json["provider_output"]["exit_status"] == 23
    assert run_json["provider_output"]["stderr"] =~ "Fake Codex failed"

    task_markdown = File.read!(Path.join([repository["path"], "symphonia", "tasks", "SYM-1.md"]))
    refute task_markdown =~ "Fake Codex failed"
  end

  test "codex changes to only excluded metadata fail cleanly", %{
    registry_path: registry_path,
    repository: repository,
    runs_root: runs_root,
    task: task
  } do
    System.put_env("FAKE_CODEX_MODE", "excluded_only")

    result = CodingAssistant.start_run(registry_path, repository, task["key"])

    result = wait_for_run(repository, task["key"], result["run"]["id"], "failed")

    assert result["run"]["state"] == "failed"
    assert result["task"]["status"] == "paused"
    assert result["task"]["pausedReason"] == "run_failed"

    run_json = read_single_run!(runs_root)
    assert run_json["provider_output"]["change_detection"]["committable"] == []

    assert run_json["provider_output"]["change_detection"]["excluded"] == [
             "symphonia/tasks/SYM-1.md"
           ]
  end

  test "codex mixed metadata and work-product changes commit only work product", %{
    registry_path: registry_path,
    remote_path: remote_path,
    repository: repository,
    runs_root: runs_root,
    task: task
  } do
    System.put_env("FAKE_CODEX_MODE", "mixed")

    result = CodingAssistant.start_run(registry_path, repository, task["key"])

    result = wait_for_run(repository, task["key"], result["run"]["id"], "completed")

    assert result["run"]["state"] == "completed"
    assert result["task"]["handoff"]["filesChanged"] == ["app/codex-output.txt"]

    branch_files =
      git_output!([
        "--git-dir",
        remote_path,
        "ls-tree",
        "-r",
        "--name-only",
        "refs/heads/symphonia/task/sym-1"
      ])

    assert branch_files =~ "app/codex-output.txt"
    refute branch_files =~ "symphonia/tasks/SYM-1.md"

    run_json = read_single_run!(runs_root)

    assert run_json["provider_output"]["change_detection"]["excluded"] == [
             "symphonia/tasks/SYM-1.md"
           ]
  end

  test "continuation passes Clarise checklist only to Codex", %{
    prompt_file: prompt_file,
    registry_path: registry_path,
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
    assert wait_for_task_status(repository, task["key"], "in_review")["status"] == "in_review"

    prompt = File.read!(prompt_file)
    assert prompt =~ "Continuation input:"
    assert prompt =~ "Requested changes:"
    assert prompt =~ "- Make task cards less dense."
    refute prompt =~ "The card is still too dense"

    continuation_run =
      runs_root
      |> Path.join("run_*.json")
      |> Path.wildcard()
      |> Enum.map(&JSON.decode!(File.read!(&1)))
      |> Enum.find(&(&1["kind"] == "review_continuation"))

    assert continuation_run["input"] =~ "- Show the retry action only when the task is paused."
    refute continuation_run["input"] =~ "The card is still too dense"
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

  defp write_fake_codex!(path) do
    File.write!(path, """
    #!/bin/sh
    args_file="$FAKE_CODEX_ARGS_FILE"
    prompt_file="$FAKE_CODEX_PROMPT_FILE"
    repo_path=""
    last_message=""

    : > "$args_file"
    while [ "$#" -gt 0 ]; do
      printf '%s\\n' "$1" >> "$args_file"
      if [ "$1" = "--cd" ]; then
        shift
        repo_path="$1"
        printf '%s\\n' "$1" >> "$args_file"
      elif [ "$1" = "-o" ]; then
        shift
        last_message="$1"
        printf '%s\\n' "$1" >> "$args_file"
      fi
      shift
    done

    cat > "$prompt_file"

    if [ "$FAKE_CODEX_MODE" = "fail" ]; then
      echo "Fake Codex failed" >&2
      exit 23
    fi

    if [ "$FAKE_CODEX_MODE" = "excluded_only" ] || [ "$FAKE_CODEX_MODE" = "mixed" ]; then
      mkdir -p "$repo_path/symphonia/tasks"
      printf 'metadata should not be committed\\n' > "$repo_path/symphonia/tasks/SYM-1.md"
    fi

    if [ "$FAKE_CODEX_MODE" != "excluded_only" ]; then
      mkdir -p "$repo_path/app"
      printf 'Fake Codex work product\\n' > "$repo_path/app/codex-output.txt"
    fi

    if [ -n "$last_message" ]; then
      printf 'Fake Codex changed app/codex-output.txt.\\n' > "$last_message"
    fi

    printf '{"event":"done","files":["app/codex-output.txt"]}\\n'
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

  defp read_single_run!(runs_root) do
    [run_file] = Path.wildcard(Path.join(runs_root, "run_*.json"))
    JSON.decode!(File.read!(run_file))
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
