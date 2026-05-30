defmodule SymphoniaService.Runners.SelectionPolicy do
  @moduledoc """
  Runner selection policy for Coding Assistant runs.
  """

  alias SymphoniaService.Access.{Actor, AuditLog, Policy}
  alias SymphoniaService.Runners.{Capabilities, LocalService, Registry}

  def select_for_run(registry_path, repository, actor, opts \\ []) do
    requested_runner_id = Keyword.get(opts, :runner_id)

    case requested_runner_id do
      nil -> select_local_service(registry_path, repository, actor)
      "" -> select_local_service(registry_path, repository, actor)
      "local-service" -> select_local_service(registry_path, repository, actor)
      runner_id -> select_remote_runner(registry_path, repository, actor, runner_id, opts)
    end
  end

  def select_local_service(registry_path, repository, actor \\ Actor.harness()) do
    runner = LocalService.runner_metadata()

    audit_selection(
      registry_path,
      repository,
      actor,
      "runner.selected_for_run",
      runner,
      "selected"
    )

    {:ok, runner}
  end

  defp select_remote_runner(registry_path, repository, actor, runner_id, opts) do
    with {:ok, private_runner} <- Registry.get(registry_path, runner_id),
         public_runner <- Registry.public(private_runner),
         :ok <- require_online(public_runner),
         :ok <- require_capabilities(public_runner, opts),
         :ok <- require_capacity(public_runner),
         :ok <- require_permission(actor, repository),
         :ok <- require_repository_policy(repository),
         :ok <- require_execution_flag(opts) do
      runner = metadata(public_runner)

      audit_selection(
        registry_path,
        repository,
        actor,
        "runner.selected_for_run",
        runner,
        "selected"
      )

      {:ok, runner}
    else
      {:error, reason} ->
        reason = to_string(reason)
        runner = rejected_runner(registry_path, runner_id)

        audit_selection(
          registry_path,
          repository,
          actor,
          "runner.rejected_for_run",
          runner,
          reason
        )

        {:error, rejection_payload(reason)}
    end
  end

  defp require_online(%{"status" => "online"}), do: :ok
  defp require_online(%{"status" => "disabled"}), do: {:error, "runner_disabled"}
  defp require_online(%{"status" => "stale"}), do: {:error, "runner_stale"}
  defp require_online(%{"status" => "offline"}), do: {:error, "runner_offline"}
  defp require_online(_runner), do: {:error, "runner_unavailable"}

  defp require_capabilities(%{"capabilities" => capabilities}, opts) do
    workspace_provider = Keyword.get(opts, :workspace_provider, "local_git_worktree")

    cond do
      capabilities["codexAppServer"] != true ->
        {:error, "missing_codex_capability"}

      workspace_provider == "local_git_worktree" and capabilities["localGitWorktree"] != true ->
        {:error, "missing_workspace_capability"}

      workspace_provider == "experimental_sandbox" and capabilities["experimentalSandbox"] != true ->
        {:error, "missing_workspace_capability"}

      true ->
        :ok
    end
  end

  defp require_capacity(%{"currentRuns" => current, "limits" => %{"maxConcurrentRuns" => max}})
       when is_integer(current) and is_integer(max) and current < max,
       do: :ok

  defp require_capacity(_runner), do: {:error, "runner_capacity_full"}

  defp require_permission(actor, repository) do
    case Policy.authorize(actor, "runner.use_remote", repository) do
      :ok -> :ok
      {:error, _payload} -> {:error, "permission_denied"}
    end
  end

  defp require_repository_policy(repository) do
    if remote_execution_allowed?(repository) do
      :ok
    else
      {:error, "remote_execution_disabled"}
    end
  end

  defp require_execution_flag(opts) do
    if Keyword.get(opts, :allow_remote_execution, false) == true do
      :ok
    else
      {:error, "remote_execution_disabled"}
    end
  end

  defp remote_execution_allowed?(repository) when is_map(repository) do
    repository["remoteExecutionAllowed"] == true or repository["remote_execution_allowed"] == true or
      get_in(repository, ["automation", "remoteExecutionAllowed"]) == true or
      get_in(repository, ["automation", "remote_execution_allowed"]) == true
  end

  defp remote_execution_allowed?(_repository), do: false

  defp metadata(public_runner) do
    %{
      "id" => public_runner["id"],
      "mode" => public_runner["mode"],
      "name" => public_runner["name"]
    }
  end

  defp rejected_runner(registry_path, runner_id) do
    case Registry.get(registry_path, runner_id) do
      {:ok, runner} -> metadata(Registry.public(runner))
      _ -> %{"id" => runner_id, "mode" => "remote_runner", "name" => "Remote runner"}
    end
  end

  defp rejection_payload("permission_denied") do
    {403,
     %{
       "error" => "You do not have permission to use remote runners for this repository.",
       "reasonCode" => "permission_denied",
       "permission" => "runner.use_remote"
     }}
  end

  defp rejection_payload(reason) when reason in ["runner_capacity_full"] do
    {409, %{"error" => "Requested runner has no available capacity.", "reasonCode" => reason}}
  end

  defp rejection_payload(reason) do
    {403, %{"error" => rejection_message(reason), "reasonCode" => reason}}
  end

  defp rejection_message("not_found"), do: "Requested runner was not found."
  defp rejection_message("runner_disabled"), do: "Requested runner is disabled."
  defp rejection_message("runner_stale"), do: "Requested runner heartbeat is stale."
  defp rejection_message("runner_offline"), do: "Requested runner is offline."
  defp rejection_message("missing_codex_capability"), do: "Requested runner cannot run Codex."

  defp rejection_message("missing_workspace_capability"),
    do: "Requested runner cannot use this workspace provider."

  defp rejection_message("remote_execution_disabled"),
    do: "Remote runner execution is disabled by default."

  defp rejection_message(_reason), do: "Requested runner cannot be selected for this run."

  defp audit_selection(registry_path, repository, actor, action, runner, reason_code) do
    AuditLog.record(registry_path, repository || %{"key" => "GLOBAL"}, %{
      "actor" => actor,
      "action" => action,
      "target" => %{"type" => "runner", "id" => runner["id"]},
      "result" => "completed",
      "metadata" => %{
        "runnerId" => runner["id"],
        "runnerMode" => runner["mode"],
        "capabilitySummary" => capability_summary(registry_path, runner["id"]),
        "reasonCode" => reason_code
      }
    })
  rescue
    _error -> :ok
  end

  defp capability_summary(_registry_path, "local-service"),
    do: "codex, local-worktree, validation"

  defp capability_summary(registry_path, runner_id) do
    case Registry.get(registry_path, runner_id) do
      {:ok, runner} -> Capabilities.summary(runner["capabilities"])
      _ -> "unknown"
    end
  end
end
