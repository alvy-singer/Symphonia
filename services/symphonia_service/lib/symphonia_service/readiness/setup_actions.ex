defmodule SymphoniaService.Readiness.SetupActions do
  @moduledoc """
  Explicit repository setup actions used by the readiness surface.
  """

  alias SymphoniaService.{SpecWorkspace, Workspace}
  alias SymphoniaService.Readiness.RepositoryReadiness

  def create_workflow_from_template(repository, attrs \\ %{}, opts \\ []) do
    template_id = attrs["template"] || attrs["templateId"] || attrs["id"] || "simple-pr"
    Workspace.create_workflow_from_template(repository, template_id)
    RepositoryReadiness.get(repository, opts)
  end

  def initialize_workspace(repository, opts \\ []) do
    Workspace.initialize(repository)
    RepositoryReadiness.get(repository, opts)
  end

  def initialize_spec_workspace(repository, opts \\ []) do
    repository = with_registry_path(repository, opts)
    SpecWorkspace.initialize(repository)
    RepositoryReadiness.get(repository, opts)
  end

  defp with_registry_path(repository, opts) do
    case Keyword.get(opts, :registry_path) do
      value when is_binary(value) -> Map.put(repository, "_registry_path", value)
      _ -> repository
    end
  end
end
