defmodule SymphoniaService.Runners.LocalService do
  @moduledoc """
  Synthesized runner row for the in-service local execution path.
  """

  alias SymphoniaService.CodingAssistant.{ProviderCatalog, RunEvents, RunStore}
  alias SymphoniaService.Runner.WorkspaceProviders

  @max_concurrent_runs 1

  def status(_registry_path \\ SymphoniaService.default_registry_path()) do
    codex = codex_status()
    sandbox = WorkspaceProviders.workspace_isolation_status()["experimentalSandbox"] || %{}

    %{
      "id" => "local-service",
      "name" => "Local service",
      "mode" => "local_service",
      "status" => "online",
      "lastHeartbeatAt" => now(),
      "capabilities" => %{
        "codexAppServer" => codex["ready"] == true,
        "localGitWorktree" => true,
        "experimentalSandbox" => sandbox["enabled"] == true,
        "validation" => true
      },
      "limits" => %{"maxConcurrentRuns" => @max_concurrent_runs},
      "currentRuns" => active_run_count()
    }
  end

  def runner_metadata do
    %{
      "id" => "local-service",
      "mode" => "local_service",
      "name" => "Local service"
    }
  end

  def max_concurrent_runs, do: @max_concurrent_runs

  defp codex_status do
    ProviderCatalog.readiness_status(mode: :check_only)
    |> Map.get("providers", [])
    |> Enum.find(%{}, &(&1["id"] == "codex_app_server"))
  rescue
    _error -> %{}
  end

  defp active_run_count do
    RunStore.list()
    |> Enum.count(&RunEvents.active?/1)
  rescue
    _error -> 0
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
