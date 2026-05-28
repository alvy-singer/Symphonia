defmodule SymphoniaService.Harness.Automation do
  @moduledoc """
  Repository-level opt-in state for the always-on Codex harness.
  """

  alias SymphoniaService.RepositoryRegistry

  @default_provider "codex_app_server"

  def status(repository) when is_map(repository) do
    automation = Map.get(repository, "automation") || %{}

    %{
      "enabled" => truthy?(automation["enabled"]),
      "provider" => automation["provider"] || @default_provider,
      "enabledAt" => automation["enabled_at"],
      "disabledAt" => automation["disabled_at"]
    }
    |> reject_nil()
  end

  def enabled?(repository), do: status(repository)["enabled"] == true

  def enable(registry_path, repo_key, attrs \\ %{}) do
    provider = runnable_provider(Map.get(attrs, "provider"))
    now = now()

    RepositoryRegistry.update(registry_path, repo_key, fn repository ->
      Map.put(repository, "automation", %{
        "enabled" => true,
        "provider" => provider,
        "enabled_at" => now
      })
    end)
  end

  defp runnable_provider("codex_app_server"), do: "codex_app_server"
  defp runnable_provider(_provider), do: @default_provider

  def disable(registry_path, repo_key) do
    now = now()

    RepositoryRegistry.update(registry_path, repo_key, fn repository ->
      automation = Map.get(repository, "automation") || %{}

      Map.put(repository, "automation", %{
        "enabled" => false,
        "provider" => automation["provider"] || @default_provider,
        "enabled_at" => automation["enabled_at"],
        "disabled_at" => now
      })
    end)
  end

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_), do: false

  defp reject_nil(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
