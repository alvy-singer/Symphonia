defmodule SymphoniaService.Runners.RepositoryPolicy do
  @moduledoc """
  Repository-level remote execution policy.

  Remote execution is default-off and stored in the private repository registry,
  not in repository Markdown.
  """

  alias SymphoniaService.RepositoryRegistry

  def remote_execution_allowed?(repository) when is_map(repository) do
    repository["remoteExecutionAllowed"] == true or repository["remote_execution_allowed"] == true or
      get_in(repository, ["automation", "remoteExecutionAllowed"]) == true or
      get_in(repository, ["automation", "remote_execution_allowed"]) == true
  end

  def remote_execution_allowed?(_repository), do: false

  def public(repository) when is_map(repository) do
    %{
      "remoteExecutionAllowed" => remote_execution_allowed?(repository),
      "allowedRunnerIds" => allowed_runner_ids(repository),
      "allowedSandboxProviders" => allowed_sandbox_providers(repository),
      "allowedCodingAssistantProviders" => allowed_coding_assistant_providers(repository),
      "requireTrustedRunner" => true,
      "secretScopesAllowed" => secret_scopes_allowed(repository)
    }
  end

  def set_remote_execution(registry_path, repo_key, allowed?) when is_boolean(allowed?) do
    RepositoryRegistry.update(registry_path, repo_key, fn repository ->
      Map.put(repository, "remoteExecutionAllowed", allowed?)
    end)
  end

  def update_policy(registry_path, repo_key, attrs) when is_map(attrs) do
    RepositoryRegistry.update(registry_path, repo_key, fn repository ->
      repository
      |> maybe_put_boolean("remoteExecutionAllowed", attrs["remoteExecutionAllowed"])
      |> maybe_put_list(
        "allowedRunnerIds",
        attrs["allowedRunnerIds"] || attrs["allowed_runner_ids"]
      )
      |> maybe_put_list(
        "allowedSandboxProviders",
        attrs["allowedSandboxProviders"] || attrs["allowed_sandbox_providers"]
      )
      |> maybe_put_list(
        "allowedCodingAssistantProviders",
        attrs["allowedCodingAssistantProviders"] || attrs["allowed_coding_assistant_providers"]
      )
      |> maybe_put_list(
        "secretScopesAllowed",
        attrs["secretScopesAllowed"] || attrs["secret_scopes_allowed"]
      )
      |> Map.put("requireTrustedRunner", true)
    end)
  end

  def allowed_runner_ids(repository) when is_map(repository) do
    list(repository["allowedRunnerIds"] || repository["allowed_runner_ids"])
  end

  def allowed_runner_ids(_repository), do: []

  def runner_allowed?(repository, runner_id) when is_binary(runner_id) do
    runner_id in allowed_runner_ids(repository)
  end

  def runner_allowed?(_repository, _runner_id), do: false

  def allowed_sandbox_providers(repository) when is_map(repository) do
    list(repository["allowedSandboxProviders"] || repository["allowed_sandbox_providers"])
  end

  def allowed_sandbox_providers(_repository), do: []

  def sandbox_provider_allowed?(repository, provider) when is_binary(provider) do
    provider in allowed_sandbox_providers(repository)
  end

  def sandbox_provider_allowed?(_repository, _provider), do: false

  def allowed_coding_assistant_providers(repository) when is_map(repository) do
    case repository["allowedCodingAssistantProviders"] ||
           repository["allowed_coding_assistant_providers"] do
      value when is_list(value) -> list(value)
      _other -> ["codex_app_server"]
    end
  end

  def allowed_coding_assistant_providers(_repository), do: ["codex_app_server"]

  def coding_assistant_provider_allowed?(_repository, "codex_app_server"), do: true

  def coding_assistant_provider_allowed?(repository, provider) when is_binary(provider) do
    provider in allowed_coding_assistant_providers(repository)
  end

  def coding_assistant_provider_allowed?(_repository, _provider), do: false

  def secret_scopes_allowed(repository) when is_map(repository) do
    list(repository["secretScopesAllowed"] || repository["secret_scopes_allowed"])
  end

  def secret_scopes_allowed(_repository), do: []

  defp maybe_put_boolean(repository, key, value) when is_boolean(value),
    do: Map.put(repository, key, value)

  defp maybe_put_boolean(repository, _key, _value), do: repository

  defp maybe_put_list(repository, key, value) when is_list(value) do
    Map.put(repository, key, list(value))
  end

  defp maybe_put_list(repository, _key, _value), do: repository

  defp list(value) when is_list(value) do
    value
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.slice(&1, 0, 120))
  end

  defp list(_value), do: []
end
