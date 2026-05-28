defmodule SymphoniaService.CodingAssistant.CodexProvider do
  @moduledoc """
  Real Coding Assistant provider backed by `codex exec`.
  """

  @behaviour SymphoniaService.CodingAssistant.Provider

  alias SymphoniaService.CodingAssistant.{
    BranchManager,
    ChangeDetector,
    ContextPack,
    HandoffBuilder,
    RunStore
  }

  @default_timeout_ms 900_000

  @impl true
  def id, do: "codex"

  @impl true
  def preflight(repository, task, _params) do
    with {:ok, _bin} <- codex_executable(),
         :ok <- branch_preflight(repository, task) do
      :ok
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  @impl true
  def run(repository, task, run, params) do
    if force_failure?(params) do
      {:error, "The Coding Assistant could not produce a reviewable handoff."}
    else
      with {:ok, _bin} <- codex_executable(),
           :ok <- branch_preflight(repository, task) do
        BranchManager.with_task_branch_worktree(repository, task, fn context ->
          RunStore.mark_step(run, "Preparing repository")
          prompt = ContextPack.render_prompt(repository, task, context, params, mode: :codex)

          with {:ok, output} <- invoke_codex(run, context.repo_path, prompt),
               {:ok, changes} <- detect_and_clean_changes(run, context.repo_path),
               :ok <- ensure_committable_changes(changes),
               :ok <- commit_and_push(run, context, task, changes) do
            handoff =
              HandoffBuilder.build_from_changes(
                task,
                context,
                changes["committable"],
                output["last_message"]
              )

            {:ok, handoff}
          else
            {:error, reason} -> {:error, reason}
          end
        end)
      end
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp branch_preflight(repository, task) do
    BranchManager.ensure_repo_ready_for_task_branch!(repository, task)
    :ok
  end

  defp detect_and_clean_changes(run, repo_path) do
    RunStore.mark_step(run, "Detecting changed files")
    changes = ChangeDetector.detect!(repo_path)
    RunStore.record_provider_output(run, %{"change_detection" => changes})
    BranchManager.revert_paths!(repo_path, changes["excluded"])
    {:ok, changes}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp ensure_committable_changes(%{"committable" => []}) do
    {:error, "The Coding Assistant did not produce any files that can be reviewed."}
  end

  defp ensure_committable_changes(_changes), do: :ok

  defp commit_and_push(run, context, task, changes) do
    RunStore.mark_step(run, "Creating branch")
    BranchManager.commit_files!(context, task, changes["committable"])
    BranchManager.push_task_branch!(context)
    :ok
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp invoke_codex(run, repo_path, prompt) do
    with {:ok, bin} <- codex_executable() do
      prompt_path = temp_file_path("prompt")
      stderr_path = temp_file_path("stderr")
      runner_path = temp_runner_path()
      last_message_path = temp_file_path("last-message")

      File.write!(prompt_path, prompt)
      write_runner!(runner_path)

      args = codex_args(repo_path, last_message_path)

      env = [
        {"SYMPHONIA_CODEX_PROMPT_FILE", prompt_path},
        {"SYMPHONIA_CODEX_STDERR_FILE", stderr_path}
      ]

      try do
        {stdout, status} = run_with_timeout(runner_path, [bin | args], env)
        stderr = read_if_exists(stderr_path)
        last_message = read_if_exists(last_message_path)

        output = %{
          "argv" => [bin | args],
          "exit_status" => status,
          "jsonl" => stdout,
          "last_message" => String.trim(last_message),
          "stderr" => stderr
        }

        RunStore.record_provider_output(run, output)

        if status == 0 do
          {:ok, output}
        else
          {:error, codex_error(output)}
        end
      after
        File.rm(prompt_path)
        File.rm(stderr_path)
        File.rm(runner_path)
        File.rm(last_message_path)
      end
    end
  end

  defp run_with_timeout(command, args, env) do
    timeout = timeout_ms()

    task =
      Task.async(fn ->
        System.cmd(command, args, env: env, stderr_to_stdout: false)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {"", 124}
    end
  end

  defp codex_args(repo_path, last_message_path) do
    base = [
      "exec",
      "--cd",
      repo_path,
      "--json",
      "--sandbox",
      "workspace-write",
      "--ask-for-approval",
      "never",
      "-o",
      last_message_path
    ]

    base ++ model_args() ++ ["-"]
  end

  defp model_args do
    case System.get_env("SYMPHONIA_CODEX_MODEL") do
      value when is_binary(value) and value != "" -> ["--model", value]
      _ -> []
    end
  end

  defp codex_executable do
    configured = System.get_env("SYMPHONIA_CODEX_BIN") || "codex"

    cond do
      Path.type(configured) == :absolute and File.exists?(configured) ->
        {:ok, configured}

      executable = System.find_executable(configured) ->
        {:ok, executable}

      true ->
        {:error,
         "The Coding Assistant can't start because Codex is not available on this computer."}
    end
  end

  defp codex_error(%{"exit_status" => 124}) do
    "The Coding Assistant could not finish before the Codex run timed out."
  end

  defp codex_error(output) do
    [output["stderr"], output["last_message"], output["jsonl"]]
    |> Enum.find_value(fn value ->
      value = to_string(value) |> String.trim()
      if value == "", do: nil, else: value
    end)
    |> case do
      nil -> "The Coding Assistant run failed."
      message -> message
    end
  end

  defp write_runner!(path) do
    File.write!(path, """
    #!/bin/sh
    exec "$@" < "$SYMPHONIA_CODEX_PROMPT_FILE" 2> "$SYMPHONIA_CODEX_STDERR_FILE"
    """)

    File.chmod(path, 0o700)
  end

  defp temp_file_path(kind) do
    Path.join(System.tmp_dir!(), "symphonia-codex-#{kind}-#{System.unique_integer([:positive])}")
  end

  defp temp_runner_path, do: temp_file_path("runner")

  defp read_if_exists(path) do
    case File.read(path) do
      {:ok, body} -> body
      {:error, _reason} -> ""
    end
  end

  defp timeout_ms do
    case Integer.parse(System.get_env("SYMPHONIA_CODEX_TIMEOUT_MS") || "") do
      {value, ""} when value > 0 -> value
      _ -> @default_timeout_ms
    end
  end

  defp force_failure?(params) do
    Map.get(params, "forceFailure") == true or Map.get(params, "force_failure") == true
  end
end
