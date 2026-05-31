defmodule SymphoniaService.Sandbox.OpenSandboxConfig do
  @moduledoc """
  Private OpenSandbox provider configuration.

  V1 keeps OpenSandbox credentials as environment-backed secret references. The
  public readiness surface exposes configured/missing status only, never values.
  """

  alias SymphoniaService.Secrets.ReferenceStore

  @provider "opensandbox"
  @label "OpenSandbox"
  @default_image "opensandbox/code-interpreter:v1.0.2"
  @default_ttl_seconds 1_800
  @default_timeout_seconds 900
  @default_cpu "2"
  @default_memory "4Gi"
  @default_runner_command "symphonia-sandbox-runner --context /workspace/.symphonia/context-pack.json --result /workspace/.symphonia/result.json"

  def provider_id, do: @provider
  def label, do: @label

  def load(opts) when is_map(opts) do
    repository = opts["repository"] || opts[:repository] || %{}
    registry_path = opts["registry_path"] || opts[:registry_path]
    references = secret_references(registry_path, repository)
    reference = select_api_key_reference(references, opts, repository)
    env_name = reference && reference["envName"]
    api_key = if is_binary(env_name), do: System.get_env(env_name)

    %{
      "provider" => @provider,
      "label" => @label,
      "lifecycleUrl" => lifecycle_url(opts),
      "execdUrl" => string_config(opts, "execdUrl", "SYMPHONIA_OPENSANDBOX_EXECD_URL"),
      "apiKey" => api_key,
      "apiKeyRef" => reference && reference["id"],
      "apiKeyRefConfigured" => configured_reference?(reference),
      "apiKeyEnvName" => env_name,
      "image" => string_config(opts, "image", "SYMPHONIA_OPENSANDBOX_IMAGE") || @default_image,
      "ttlSeconds" =>
        integer_config(opts, "ttlSeconds", "SYMPHONIA_OPENSANDBOX_TTL_SECONDS", @default_ttl_seconds),
      "timeoutSeconds" =>
        integer_config(
          opts,
          "timeoutSeconds",
          "SYMPHONIA_OPENSANDBOX_TIMEOUT_SECONDS",
          @default_timeout_seconds
        ),
      "resourceLimits" => %{
        "cpu" => string_config(opts, "cpu", "SYMPHONIA_OPENSANDBOX_CPU") || @default_cpu,
        "memory" =>
          string_config(opts, "memory", "SYMPHONIA_OPENSANDBOX_MEMORY") || @default_memory
      },
      "workspaceMode" => "source_bundle",
      "egressMode" =>
        string_config(opts, "egressMode", "SYMPHONIA_OPENSANDBOX_EGRESS_MODE") || "restricted",
      "runnerCommand" =>
        string_config(opts, "runnerCommand", "SYMPHONIA_OPENSANDBOX_RUNNER_COMMAND") ||
          @default_runner_command,
      "resultPath" =>
        string_config(opts, "resultPath", "SYMPHONIA_OPENSANDBOX_RESULT_PATH") ||
          "/workspace/.symphonia/result.json",
      "contextPath" => "/workspace/.symphonia/context-pack.json",
      "sourceBundlePath" => "/workspace/source.tar"
    }
  end

  def readiness(opts) when is_map(opts) do
    config = load(opts)
    endpoint? = present?(config["lifecycleUrl"])
    ref? = present?(config["apiKeyRef"])
    credential? = config["apiKeyRefConfigured"] == true

    {ready?, status, reason} =
      cond do
        not endpoint? ->
          {false, "not_configured", "opensandbox_endpoint_missing"}

        not ref? ->
          {false, "not_configured", "opensandbox_api_key_reference_missing"}

        not credential? ->
          {false, "not_configured", "opensandbox_api_key_missing"}

        true ->
          {true, "ready", nil}
      end

    %{
      "configured" => endpoint? and ref?,
      "ready" => ready?,
      "status" => status,
      "reason" => reason,
      "provider" => @provider,
      "label" => @label,
      "mode" => "manual_only",
      "workspaceMode" => config["workspaceMode"],
      "egressMode" => config["egressMode"],
      "resourceLimits" => config["resourceLimits"],
      "ttlSeconds" => config["ttlSeconds"],
      "timeoutSeconds" => config["timeoutSeconds"],
      "credential" => if(credential?, do: "environment_reference_configured", else: "missing")
    }
  end

  def private_session(config) do
    Map.take(config, [
      "provider",
      "label",
      "lifecycleUrl",
      "execdUrl",
      "apiKey",
      "image",
      "ttlSeconds",
      "timeoutSeconds",
      "resourceLimits",
      "workspaceMode",
      "egressMode",
      "runnerCommand",
      "resultPath",
      "contextPath",
      "sourceBundlePath"
    ])
  end

  def public_config(config) do
    config
    |> Map.take([
      "provider",
      "label",
      "image",
      "ttlSeconds",
      "timeoutSeconds",
      "resourceLimits",
      "workspaceMode",
      "egressMode"
    ])
  end

  defp lifecycle_url(opts) do
    opts
    |> string_config("endpoint", "SYMPHONIA_OPENSANDBOX_ENDPOINT")
    |> normalize_lifecycle_url()
  end

  defp normalize_lifecycle_url(nil), do: nil

  defp normalize_lifecycle_url(value) when is_binary(value) do
    value = value |> String.trim() |> String.trim_trailing("/")

    cond do
      value == "" -> nil
      String.ends_with?(value, "/v1") -> value
      true -> value <> "/v1"
    end
  end

  defp secret_references(nil, _repository), do: []

  defp secret_references(registry_path, repository) do
    ReferenceStore.list(registry_path, repository)
  rescue
    _error -> []
  end

  defp select_api_key_reference(references, opts, repository) do
    requested_id =
      opts["apiKeyRef"] || opts["api_key_ref"] ||
        get_in(repository, ["sandboxProviderConfig", @provider, "apiKeyRef"]) ||
        get_in(repository, ["sandbox_provider_config", @provider, "api_key_ref"]) ||
        repository["openSandboxApiKeyRef"]

    cond do
      is_binary(requested_id) and requested_id != "" ->
        Enum.find(references, &(&1["id"] == requested_id))

      true ->
        Enum.find(references, &(&1["scope"] == "sandbox.provider"))
    end
  end

  defp configured_reference?(%{"configured" => true}), do: true
  defp configured_reference?(_reference), do: false

  defp string_config(opts, key, env_name) do
    value =
      opts[key] ||
        opts[Macro.underscore(key)] ||
        get_in(opts, ["opensandbox", key]) ||
        System.get_env(env_name)

    case value do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: nil, else: value

      _other ->
        nil
    end
  end

  defp integer_config(opts, key, env_name, default) do
    value = string_config(opts, key, env_name)

    case Integer.parse(to_string(value || "")) do
      {integer, ""} when integer > 0 -> integer
      _other -> default
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
