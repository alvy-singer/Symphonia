defmodule SymphoniaService do
  @moduledoc """
  Filesystem-backed task service for the Symphonia milestone-one slice.

  The service owns Markdown parsing, task lifecycle transitions, and optional
  HTTP access. It intentionally has no external dependencies so it can run in
  this prototype without package setup.
  """

  def default_repositories_root do
    System.get_env("SYMPHONIA_REPOSITORIES_ROOT") || default_fixture_root()
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
