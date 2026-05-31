defmodule SymphoniaService.Sandbox.Registry do
  @moduledoc """
  Resolves configured sandbox providers without creating sandbox sessions.
  """

  alias SymphoniaService.Sandbox.{FakeProvider, OpenSandboxConfig, OpenSandboxProvider, Session}

  @fake "fake_sandbox"
  @opensandbox "opensandbox"

  def fake_provider, do: @fake
  def opensandbox_provider, do: @opensandbox

  def resolve(repository_or_policy) do
    provider_id = provider_id(repository_or_policy)

    case provider_id do
      @fake -> {:ok, FakeProvider}
      @opensandbox -> {:ok, OpenSandboxProvider}
      nil -> {:error, "sandbox_provider_not_configured"}
      "" -> {:error, "sandbox_provider_not_configured"}
      _other -> {:error, "sandbox_provider_not_supported"}
    end
  end

  def readiness(repository_or_policy, registry_path \\ nil) do
    provider_id = provider_id(repository_or_policy)

    base = %{
      "configured" => is_binary(provider_id) and provider_id != "",
      "provider" => provider_id,
      "label" => Session.label(provider_id),
      "passive" => true
    }

    case resolve(repository_or_policy) do
      {:ok, OpenSandboxProvider} ->
        Map.merge(
          base,
          OpenSandboxProvider.readiness(%{
            "repository" => repository_or_policy,
            "registry_path" => registry_path
          })
        )

      {:ok, provider} ->
        Map.merge(base, provider.readiness(%{}))

      {:error, reason} -> Map.merge(base, %{"ready" => false, "reason" => reason})
    end
  end

  def provider_label(repository_or_policy) do
    repository_or_policy
    |> provider_id()
    |> Session.label()
  end

  def provider_id(%{"sandboxProvider" => provider}) when is_binary(provider), do: provider
  def provider_id(%{"sandbox_provider" => provider}) when is_binary(provider), do: provider
  def provider_id(%{"automation" => %{"sandboxProvider" => provider}}) when is_binary(provider), do: provider
  def provider_id(%{"automation" => %{"sandbox_provider" => provider}}) when is_binary(provider), do: provider
  def provider_id(_value), do: nil

  def known_provider?(@fake), do: true
  def known_provider?(@opensandbox), do: true
  def known_provider?(_provider), do: false

  def default_provider, do: OpenSandboxConfig.provider_id()
end
