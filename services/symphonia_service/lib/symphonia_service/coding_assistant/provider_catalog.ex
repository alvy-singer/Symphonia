defmodule SymphoniaService.CodingAssistant.ProviderCatalog do
  @moduledoc """
  Public provider contract and readiness surface.

  Harness V2 can execute only Codex App Server. Other assistants may be shown in
  product surfaces, but they are intentionally not runnable by the daemon until
  they satisfy the full review-first execution contract.
  """

  alias SymphoniaService.CodingAssistant.{AppServerProvider, CodexProvider, GeminiCliProvider}

  @required_capabilities ~w(
    context_pack
    persistent_workspace
    streamed_public_steps
    change_detection
    validation_pipeline
    curated_summary
    review_branch
    handoff
    retry_classification
  )

  @future_providers [
    %{
      "id" => "claude_code",
      "label" => "Claude Code",
      "status" => "experimental",
      "reason" => "Coming later. Not runnable by Harness V2."
    },
    %{
      "id" => "cursor",
      "label" => "Cursor",
      "status" => "experimental",
      "reason" => "Coming later. Missing execution adapter."
    }
  ]

  def required_capabilities, do: @required_capabilities

  def harness_runnable_provider, do: AppServerProvider

  def harness_status(opts \\ []) do
    %{
      "defaultProvider" => "codex_app_server",
      "runnableProvider" => harness_runnable_provider().id(),
      "providers" => providers(opts)
    }
  end

  def readiness_status(opts \\ []), do: harness_status(opts)

  def providers(opts \\ []) do
    [
      provider_status(AppServerProvider, opts, harness_runnable?: true),
      manual_provider_status(GeminiCliProvider, opts),
      legacy_provider_status(opts)
      | Enum.map(@future_providers, &future_provider_status/1)
    ]
    |> List.flatten()
  end

  defp provider_status(provider, opts, policy_opts) do
    readiness = safe_readiness(provider, opts)
    capabilities = normalize_capabilities(provider.capabilities())
    missing = missing_capabilities(capabilities)
    harness_runnable? = Keyword.get(policy_opts, :harness_runnable?, false) and missing == []
    ready? = readiness["ready"] == true
    configured? = readiness["configured"] == true

    %{
      "id" => provider.id(),
      "label" => provider.label(),
      "configured" => configured?,
      "ready" => ready?,
      "runnable" => harness_runnable? and ready?,
      "runnableByHarness" => harness_runnable?,
      "status" => provider_status_value(ready?, configured?, harness_runnable?),
      "reason" => provider_reason(provider, readiness, harness_runnable?),
      "capabilities" => capabilities,
      "missingCapabilities" => missing
    }
    |> maybe_put_codex_readiness(readiness)
  end

  defp manual_provider_status(provider, opts) do
    readiness = safe_readiness(provider, opts)
    capabilities = normalize_capabilities(provider.capabilities())
    missing = missing_capabilities(capabilities)
    ready? = readiness["ready"] == true
    configured? = readiness["configured"] == true

    %{
      "id" => provider.id(),
      "label" => provider.label(),
      "configured" => configured?,
      "ready" => ready?,
      "runnable" => ready? and missing == [],
      "runnableByHarness" => false,
      "manualOnly" => true,
      "executionMode" => readiness["executionMode"] || "cloud_sandbox",
      "workspaceProvider" => readiness["workspaceProvider"] || "opensandbox",
      "status" => manual_status_value(ready?, configured?),
      "reason" => manual_provider_reason(provider, readiness),
      "capabilities" => capabilities,
      "missingCapabilities" => missing
    }
  end

  defp legacy_provider_status(opts) do
    readiness = safe_readiness(CodexProvider, opts)
    capabilities = normalize_capabilities(CodexProvider.capabilities())
    missing = missing_capabilities(capabilities)

    %{
      "id" => CodexProvider.id(),
      "label" => CodexProvider.label(),
      "configured" => readiness["configured"] == true,
      "ready" => false,
      "runnable" => false,
      "runnableByHarness" => false,
      "status" => "disabled",
      "reason" => "Legacy provider does not satisfy Harness V2 review-first contract.",
      "capabilities" => capabilities,
      "missingCapabilities" => missing
    }
  end

  defp future_provider_status(provider) do
    capabilities = normalize_capabilities(%{})

    %{
      "id" => provider["id"],
      "label" => provider["label"],
      "configured" => false,
      "ready" => false,
      "runnable" => false,
      "runnableByHarness" => false,
      "status" => provider["status"],
      "reason" => provider["reason"],
      "capabilities" => capabilities,
      "missingCapabilities" => missing_capabilities(capabilities)
    }
  end

  defp safe_readiness(provider, opts) do
    provider.readiness(opts)
  rescue
    error ->
      %{
        "configured" => false,
        "ready" => false,
        "reason" => Exception.message(error)
      }
  end

  defp normalize_capabilities(capabilities) when is_map(capabilities) do
    Map.new(@required_capabilities, fn capability ->
      {capability, Map.get(capabilities, capability) == true}
    end)
  end

  defp normalize_capabilities(_capabilities), do: normalize_capabilities(%{})

  defp missing_capabilities(capabilities) do
    capabilities
    |> Enum.reject(fn {_capability, supported?} -> supported? end)
    |> Enum.map(fn {capability, _supported?} -> capability end)
    |> Enum.sort()
  end

  defp provider_status_value(true, _configured?, true), do: "ready"
  defp provider_status_value(_ready?, false, true), do: "not_configured"
  defp provider_status_value(_ready?, _configured?, true), do: "blocked"
  defp provider_status_value(_ready?, _configured?, false), do: "disabled"

  defp manual_status_value(true, _configured?), do: "ready"
  defp manual_status_value(_ready?, false), do: "not_configured"
  defp manual_status_value(_ready?, _configured?), do: "blocked"

  defp provider_reason(provider, readiness, true) do
    cond do
      readiness["ready"] == true ->
        "Ready for local Codex runs."

      readiness["configured"] != true ->
        "#{provider.label()} needs setup."

      readiness["schemaAvailable"] == false ->
        "Codex App Server schema is unavailable."

      readiness["binaryAvailable"] == false ->
        safe_reason(readiness["reason"] || "#{provider.label()} is unavailable.")

      true ->
        safe_reason(readiness["reason"] || "#{provider.label()} is blocked.")
    end
  end

  defp provider_reason(_provider, readiness, false) do
    safe_reason(readiness["reason"] || "Not runnable by Harness V2.")
  end

  defp manual_provider_reason(_provider, %{"ready" => true}) do
    "Manual OpenSandbox runs can use this provider."
  end

  defp manual_provider_reason(provider, readiness) do
    safe_reason(readiness["reason"] || "#{provider.label()} needs setup.")
  end

  defp maybe_put_codex_readiness(%{"id" => "codex_app_server"} = provider, readiness) do
    provider
    |> Map.put("schemaAvailable", readiness["schemaAvailable"] == true)
    |> Map.put("binaryAvailable", readiness["binaryAvailable"] == true)
    |> Map.put("daemonReachable", readiness["daemonReachable"])
  end

  defp maybe_put_codex_readiness(provider, _readiness), do: provider

  defp safe_reason(reason) when is_binary(reason) do
    reason
    |> String.replace(~r/[A-Z_]{3,}[A-Z0-9_]*=/, "setting=")
    |> String.replace(~r/(\/[A-Za-z0-9._@%+~:-]+)+/, "[local path]")
    |> String.replace(~r/`[^`]+`/, "setup command")
  end

  defp safe_reason(_reason), do: "Provider readiness could not be confirmed."
end
