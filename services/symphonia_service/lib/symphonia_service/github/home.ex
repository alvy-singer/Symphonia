defmodule SymphoniaService.GitHub.Home do
  @moduledoc """
  Local storage root for GitHub integration metadata.
  """

  def path(opts \\ []) do
    opts[:home] ||
      Application.get_env(:symphonia_service, :github_home) ||
      System.get_env("SYMPHONIA_GITHUB_HOME") ||
      default_path()
  end

  defp default_path do
    base =
      System.get_env("SYMPHONIA_HOME") ||
        Path.join(System.user_home!(), ".symphonia")

    Path.join(base, "github")
  end
end
