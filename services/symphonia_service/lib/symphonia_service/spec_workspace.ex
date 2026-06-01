defmodule SymphoniaService.SpecWorkspace do
  @moduledoc """
  Repo-backed Markdown spec workspace.

  This extends the older workspace folders with a separate layer for codebase
  maps, milestones, discussions, requirements, plans, and decisions.
  """

  alias SymphoniaService.{PrivateWorkspace}
  alias SymphoniaService.SpecWorkspace.{Index, Store}

  def statuses, do: Store.statuses()
  def artifact_types, do: Enum.uniq(Store.artifact_types() ++ PrivateWorkspace.artifact_kinds())

  def state(repository) do
    if private_enabled?(repository),
      do: PrivateWorkspace.state(repository),
      else: Store.state(repository)
  end

  def initialize(repository) do
    if private_enabled?(repository),
      do: PrivateWorkspace.initialize(repository),
      else: Store.initialize(repository)
  end

  def list_artifacts(repository) do
    if private_enabled?(repository) do
      repo_artifacts = Store.list_artifacts(repository) |> Map.drop(private_types())
      Map.merge(repo_artifacts, PrivateWorkspace.list_artifacts(repository))
    else
      Store.list_artifacts(repository)
    end
  end

  def list_artifacts(repository, type) do
    if private_enabled?(repository) and private_type?(type) do
      PrivateWorkspace.list_artifacts(repository, type)
    else
      Store.list_artifacts(repository, type)
    end
  end

  def read_artifact(repository, type, id) do
    if private_enabled?(repository) and private_type?(type) do
      PrivateWorkspace.read_artifact(repository, type, id)
    else
      Store.read_artifact(repository, type, id)
    end
  end

  def update_artifact(repository, type, id, patch) do
    if private_enabled?(repository) and private_type?(type) do
      PrivateWorkspace.update_artifact(repository, type, id, patch)
    else
      Store.update_artifact(repository, type, id, patch)
    end
  end

  def sections(repository), do: Index.sections(repository)

  def create_milestone(repository, attrs \\ %{}),
    do: create_artifact(repository, "milestone", attrs)

  def create_requirement(repository, attrs \\ %{}),
    do: Store.create_artifact(repository, "requirements", attrs)

  def create_plan(repository, attrs \\ %{}), do: create_artifact(repository, "plan", attrs)

  def create_decision(repository, attrs \\ %{}),
    do: create_artifact(repository, "decision", attrs)

  def create_task_brief(repository, attrs \\ %{}),
    do: Store.create_artifact(repository, "task_brief", attrs)

  def create_artifact(repository, type, attrs) do
    if private_enabled?(repository) and private_type?(type) do
      PrivateWorkspace.create_artifact(repository, type, attrs)
    else
      Store.create_artifact(repository, type, attrs)
    end
  end

  def create_artifact(repository, type, id, attrs) do
    if private_enabled?(repository) and private_type?(type) do
      PrivateWorkspace.create_artifact(repository, type, id, attrs)
    else
      Store.create_artifact(repository, type, id, attrs)
    end
  end

  def create_or_update_artifact(repository, type, id, attrs) do
    if private_enabled?(repository) and private_type?(type) do
      PrivateWorkspace.create_or_update_artifact(repository, type, id, attrs)
    else
      Store.create_or_update_artifact(repository, type, id, attrs)
    end
  end

  def artifact_exists?(repository, type, id) do
    if private_enabled?(repository) and private_type?(type) do
      PrivateWorkspace.artifact_exists?(repository, type, id)
    else
      Store.artifact_exists?(repository, type, id)
    end
  end

  def next_id(repository, type) do
    if private_enabled?(repository) and private_type?(type) do
      PrivateWorkspace.next_id(repository, type)
    else
      Store.next_id(repository, type)
    end
  end

  def private_enabled?(repository) when is_map(repository) do
    is_binary(repository["_registry_path"]) or is_binary(repository["registry_path"]) or
      repository["privateWorkspace"] == true
  end

  def private_enabled?(_repository), do: false

  def private_type?(type), do: type in private_types()
  defp private_types, do: PrivateWorkspace.artifact_kinds()
end
