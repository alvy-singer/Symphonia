defmodule SymphoniaService.Sandbox.Policy do
  @moduledoc """
  Repository-local sandbox execution policy.

  Sandbox execution is default-off and independent from remote runner execution.
  """

  alias SymphoniaService.Access.{Actor, Policy}
  alias SymphoniaService.Harness.Daemon
  alias SymphoniaService.RepositoryRegistry
  alias SymphoniaService.Runners.RepositoryPolicy
  alias SymphoniaService.Sandbox.Registry

  @execution_mode "cloud_sandbox"

  def execution_mode, do: @execution_mode

  def requested?(payload) when is_map(payload) do
    payload["executionMode"] == @execution_mode or payload["execution_mode"] == @execution_mode
  end

  def requested?(_payload), do: false

  def allowed?(repository) when is_map(repository) do
    repository["sandboxExecutionAllowed"] == true or
      repository["sandbox_execution_allowed"] == true or
      get_in(repository, ["automation", "sandboxExecutionAllowed"]) == true or
      get_in(repository, ["automation", "sandbox_execution_allowed"]) == true
  end

  def allowed?(_repository), do: false

  def provider(repository), do: Registry.provider_id(repository)

  def public(repository, registry_path \\ nil) when is_map(repository) do
    provider = provider(repository)
    readiness = Registry.readiness(repository, registry_path)

    %{
      "sandboxExecutionAllowed" => allowed?(repository),
      "sandboxProvider" => provider,
      "sandboxProviderLabel" => Registry.provider_label(repository),
      "sandboxProviderReadiness" => readiness
    }
  end

  def set(registry_path, repo_key, attrs) when is_map(attrs) do
    allowed? =
      attrs["sandboxExecutionAllowed"] == true or attrs["sandbox_execution_allowed"] == true

    provider =
      attrs["sandboxProvider"] || attrs["sandbox_provider"] ||
        if(allowed?, do: Registry.default_provider(), else: nil)

    RepositoryRegistry.update(registry_path, repo_key, fn repository ->
      repository
      |> Map.put("sandboxExecutionAllowed", allowed?)
      |> Map.put("sandboxProvider", normalize_provider(provider, allowed?))
    end)
  end

  def authorize_run(registry_path, repository, actor, task, params) do
    with :ok <- require_explicit_flag(params),
         :ok <- require_permissions(actor, repository),
         :ok <- require_repository_policy(repository),
         :ok <- require_provider(repository),
         :ok <- require_provider_allowed(repository),
         :ok <- require_provider_ready(repository, registry_path),
         :ok <- require_task_eligible(task),
         :ok <- require_harness_not_paused(registry_path) do
      :ok
    end
  end

  def runner_metadata(repository) do
    %{
      "id" => "cloud-sandbox",
      "mode" => "cloud_sandbox",
      "name" => Registry.provider_label(repository)
    }
  end

  defp require_explicit_flag(params) do
    if params["allowSandboxExecution"] == true or params["allow_sandbox_execution"] == true do
      :ok
    else
      {:error, {403, %{"error" => "Sandbox execution is disabled by default.", "reasonCode" => "sandbox_execution_disabled"}}}
    end
  end

  defp require_permissions(actor, repository) do
    with :ok <- Policy.authorize(actor || Actor.default(), "task.run_codex", repository),
         :ok <- authorize_sandbox_permission(actor || Actor.default(), repository) do
      :ok
    else
      {:error, payload} ->
        {:error, {403, Map.put(payload, "reasonCode", "permission_denied")}}
    end
  end

  defp authorize_sandbox_permission(actor, repository) do
    case Policy.authorize(actor, "sandbox.run", repository) do
      :ok -> :ok
      {:error, _payload} -> Policy.authorize(actor, "workspace_provider.experimental_run", repository)
    end
  end

  defp require_repository_policy(repository) do
    if allowed?(repository) do
      :ok
    else
      {:error,
       {403,
        %{
          "error" => "Sandbox execution is disabled by repository policy.",
          "reasonCode" => "sandbox_execution_disabled"
        }}}
    end
  end

  defp require_provider(repository) do
    case Registry.resolve(repository) do
      {:ok, _provider} ->
        :ok

      {:error, reason} ->
        {:error,
         {409,
          %{
            "error" => "Sandbox provider is not configured.",
            "reasonCode" => to_string(reason)
         }}}
    end
  end

  defp require_provider_allowed(repository) do
    provider = Registry.provider_id(repository)

    if RepositoryPolicy.sandbox_provider_allowed?(repository, provider) do
      :ok
    else
      {:error,
       {403,
        %{
          "error" => "Sandbox provider is not allowed for this repository.",
          "reasonCode" => "sandbox_provider_not_allowed"
        }}}
    end
  end

  defp require_provider_ready(repository, registry_path) do
    readiness = Registry.readiness(repository, registry_path)

    if readiness["ready"] == true do
      :ok
    else
      reason = readiness["reason"] || "sandbox_provider_not_configured"

      {:error,
       {409,
        %{
          "error" => "Sandbox provider is not ready.",
          "reasonCode" => to_string(reason)
        }}}
    end
  end

  defp require_task_eligible(%{"status" => status})
       when status in ["todo", "paused"],
       do: :ok

  defp require_task_eligible(_task),
    do:
      {:error,
       {409,
        %{
          "error" => "Sandbox execution is only available for assignable tasks.",
          "reasonCode" => "task_not_eligible"
        }}}

  defp require_harness_not_paused(registry_path) do
    if Daemon.peek_status(registry_path)["paused"] == true do
      {:error, {409, %{"error" => "Harness is paused.", "reasonCode" => "harness_paused"}}}
    else
      :ok
    end
  end

  defp normalize_provider(_provider, false), do: nil
  defp normalize_provider(provider, true) when provider in [nil, ""], do: Registry.default_provider()
  defp normalize_provider(provider, true) when is_binary(provider), do: provider
  defp normalize_provider(_provider, true), do: Registry.default_provider()
end
