defmodule SymphoniaService do
  @moduledoc """
  Filesystem-backed repository workspace service for Symphonia.

  The service owns the private local repository registry, workspace file
  creation, Markdown parsing, task lifecycle transitions, and optional HTTP
  access. It intentionally has no external dependencies so it can run in this
  prototype without package setup.
  """

  def default_repositories_root do
    System.get_env("SYMPHONIA_REPOSITORIES_ROOT") || default_fixture_root()
  end

  def default_registry_path do
    SymphoniaService.RepositoryRegistry.default_path()
  end

  defp default_fixture_root do
    cwd = File.cwd!()

    [
      Path.expand("fixtures/repositories", cwd),
      Path.expand("../../fixtures/repositories", cwd)
    ]
    |> Enum.find(&File.dir?/1)
    |> case do
      nil -> Path.expand("fixtures/repositories", cwd)
      path -> path
    end
  end
end
