defmodule SymphoniaService.CodingAssistant.GeminiCliProvider do
  @moduledoc """
  Manual-only Gemini CLI provider metadata and readiness.

  Gemini execution is handled by the OpenSandbox workspace provider. This module
  exposes the Coding Assistant provider contract without ever running Gemini on
  the local service.
  """

  @behaviour SymphoniaService.CodingAssistant.Provider

  alias SymphoniaService.CodingAssistant.FailureClass
  alias SymphoniaService.Secrets.ReferenceStore

  @id "gemini_cli"
  @scope "provider.gemini_cli"

  def id, do: @id
  def label, do: "Gemini CLI"
  def secret_scope, do: @scope

  def capabilities do
    %{
      "context_pack" => true,
      "persistent_workspace" => true,
      "sandbox_workspace" => true,
      "streamed_public_steps" => true,
      "change_detection" => true,
      "validation_pipeline" => true,
      "curated_summary" => true,
      "review_branch" => true,
      "handoff" => true,
      "retry_classification" => true
    }
  end

  def readiness(opts \\ []) do
    registry_path = option(opts, :registry_path)
    repository = option(opts, :repository) || %{}

    reference =
      registry_path
      |> secret_references(repository)
      |> Enum.find(&(&1["scope"] == @scope))

    configured? = reference && reference["configured"] == true

    {status, reason} =
      cond do
        is_nil(reference) -> {"not_configured", "gemini_api_key_reference_missing"}
        configured? -> {"ready", nil}
        true -> {"not_configured", "gemini_api_key_missing"}
      end

    %{
      "configured" => not is_nil(reference),
      "ready" => configured?,
      "status" => status,
      "reason" => reason,
      "provider" => @id,
      "label" => label(),
      "mode" => "manual_only",
      "executionMode" => "cloud_sandbox",
      "workspaceProvider" => "opensandbox",
      "credential" => if(configured?, do: "environment_reference_configured", else: "missing")
    }
  end

  def preflight(_repository, _task, _context), do: :ok

  def run(_repository, _task, _context, _params) do
    {:error, "gemini_cli_requires_cloud_sandbox"}
  end

  def classify_failure(reason, context \\ %{}) do
    reason
    |> to_string()
    |> String.downcase()
    |> do_classify(context)
    |> FailureClass.normalize()
  end

  defp do_classify(reason, _context) do
    cond do
      String.contains?(reason, "missing") and String.contains?(reason, "api") ->
        "setup_blocked"

      String.contains?(reason, "auth") ->
        "setup_blocked"

      String.contains?(reason, "gemini_cli_missing") ->
        "setup_blocked"

      String.contains?(reason, "opensandbox") or String.contains?(reason, "sandbox") ->
        "transient_workspace"

      String.contains?(reason, "timeout") or String.contains?(reason, "turn_limit") ->
        "transient_provider"

      String.contains?(reason, "empty_patch") or String.contains?(reason, "no_reviewable") ->
        "no_reviewable_files"

      String.contains?(reason, "validation") ->
        "validation_failed"

      true ->
        "unknown"
    end
  end

  defp secret_references(nil, _repository), do: []

  defp secret_references(registry_path, repository) do
    ReferenceStore.list(registry_path, repository)
  rescue
    _error -> []
  end

  defp option(opts, key) when is_list(opts), do: Keyword.get(opts, key)
  defp option(opts, key) when is_map(opts), do: opts[to_string(key)] || opts[key]
  defp option(_opts, _key), do: nil
end
