defmodule SymphoniaService.SpecWorkspace do
  @moduledoc """
  Repo-backed Markdown spec workspace.

  This extends the older workspace folders with a separate layer for codebase
  maps, milestones, discussions, requirements, plans, and decisions.
  """

  alias SymphoniaService.SpecWorkspace.{Decisions, Index, Milestones, Store}

  def statuses, do: Store.statuses()
  def artifact_types, do: Store.artifact_types()
  def state(repository), do: Store.state(repository)
  def initialize(repository), do: Store.initialize(repository)
  def list_artifacts(repository), do: Store.list_artifacts(repository)
  def list_artifacts(repository, type), do: Store.list_artifacts(repository, type)
  def read_artifact(repository, type, id), do: Store.read_artifact(repository, type, id)

  def update_artifact(repository, type, id, patch),
    do: Store.update_artifact(repository, type, id, patch)

  def sections(repository), do: Index.sections(repository)
  def create_milestone(repository, attrs \\ %{}), do: Milestones.create(repository, attrs)
  def create_decision(repository, attrs \\ %{}), do: Decisions.create(repository, attrs)
  def create_artifact(repository, type, id, attrs), do: Store.create_artifact(repository, type, id, attrs)
end
