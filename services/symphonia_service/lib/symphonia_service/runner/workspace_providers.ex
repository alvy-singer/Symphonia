defmodule SymphoniaService.Runner.WorkspaceProviders do
  @moduledoc """
  Resolves Coding Assistant workspace providers.

  Harness runs are intentionally pinned to the local persistent worktree. The
  experimental sandbox provider is available only for explicit manual runs when
  the feature flag is enabled.
  """

  alias SymphoniaService.Runner.{ExperimentalSandboxProvider, LocalGitWorktreeProvider}

  @local "local_git_worktree"
  @sandbox "experimental_sandbox"

  def local_provider, do: @local
  def experimental_provider, do: @sandbox

  def prepare(repository, task, run, params) do
    with {:ok, provider} <- resolve(repository, task, run, params) do
      provider.prepare(repository, task, run, params)
    end
  end

  def release(%{workspace_provider: @sandbox} = context, run),
    do: ExperimentalSandboxProvider.release(context, run)

  def release(%{"workspace_provider" => @sandbox} = context, run),
    do: ExperimentalSandboxProvider.release(context, run)

  def release(%{workspace_provider: @local} = context, run),
    do: LocalGitWorktreeProvider.release(context, run)

  def release(%{"workspace_provider" => @local} = context, run),
    do: LocalGitWorktreeProvider.release(context, run)

  def release(context, run), do: LocalGitWorktreeProvider.release(context, run)

  def resolve(_repository, _task, %{"kind" => "daemon_assignment"}, _params),
    do: {:ok, LocalGitWorktreeProvider}

  def resolve(_repository, _task, %{kind: "daemon_assignment"}, _params),
    do: {:ok, LocalGitWorktreeProvider}

  def resolve(_repository, _task, _run, params) do
    case requested_provider(params) do
      @local ->
        {:ok, LocalGitWorktreeProvider}

      @sandbox ->
        if experimental_sandbox_enabled?() do
          {:ok, ExperimentalSandboxProvider}
        else
          {:error,
           "The Coding Assistant can't start because the experimental sandbox workspace provider is disabled."}
        end

      _other ->
        {:error,
         "The Coding Assistant can't start because the workspace provider is not supported."}
    end
  end

  def review_context(%{review_context: review_context}) when is_map(review_context),
    do: review_context

  def review_context(%{"review_context" => review_context}) when is_map(review_context),
    do: review_context

  def review_context(context), do: context

  def public_label(@sandbox), do: "Experimental sandbox"
  def public_label(@local), do: "Local workspace"
  def public_label(_provider), do: "Local workspace"

  def workspace_isolation_status do
    enabled? = experimental_sandbox_enabled?()

    %{
      "local" => %{
        "id" => @local,
        "label" => public_label(@local),
        "ready" => true,
        "default" => true
      },
      "experimentalSandbox" => %{
        "id" => @sandbox,
        "label" => public_label(@sandbox),
        "enabled" => enabled?,
        "status" => if(enabled?, do: "experimental", else: "disabled")
      }
    }
  end

  def experimental_sandbox_enabled? do
    truthy?(System.get_env("SYMPHONIA_EXPERIMENTAL_SANDBOX_PROVIDER"))
  end

  defp requested_provider(params) do
    requested =
      Map.get(params || %{}, "workspace_provider") ||
        Map.get(params || %{}, "workspaceProvider") ||
        Map.get(params || %{}, :workspace_provider) ||
        Map.get(params || %{}, :workspaceProvider) ||
        System.get_env("SYMPHONIA_WORKSPACE_PROVIDER") ||
        @local

    normalize_provider(requested)
  end

  defp normalize_provider(@local), do: @local
  defp normalize_provider(@sandbox), do: @sandbox
  defp normalize_provider("local"), do: @local
  defp normalize_provider("sandbox"), do: @sandbox
  defp normalize_provider(value) when is_binary(value), do: String.trim(value)
  defp normalize_provider(_value), do: @local

  defp truthy?(value) when is_binary(value) do
    normalized = value |> String.downcase() |> String.trim()
    normalized in ["1", "true", "yes", "on"]
  end

  defp truthy?(_value), do: false
end
