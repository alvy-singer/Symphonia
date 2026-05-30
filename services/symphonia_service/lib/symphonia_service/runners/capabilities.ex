defmodule SymphoniaService.Runners.Capabilities do
  @moduledoc """
  Public-safe runner capability normalization.
  """

  @allowed ~w(codexAppServer localGitWorktree experimentalSandbox validation)

  def allowed, do: @allowed

  def sanitize(input) when is_map(input) do
    %{
      "codexAppServer" => truthy?(capability(input, "codexAppServer", "codex_app_server")),
      "localGitWorktree" => truthy?(capability(input, "localGitWorktree", "local_git_worktree")),
      "experimentalSandbox" =>
        truthy?(capability(input, "experimentalSandbox", "experimental_sandbox")),
      "validation" => truthy?(capability(input, "validation", "validation"))
    }
  end

  def sanitize(_input), do: sanitize(%{})

  def summary(capabilities) when is_map(capabilities) do
    capabilities
    |> sanitize()
    |> Enum.filter(fn {_key, enabled?} -> enabled? == true end)
    |> Enum.map(fn
      {"codexAppServer", _} -> "codex"
      {"localGitWorktree", _} -> "local-worktree"
      {"experimentalSandbox", _} -> "experimental-sandbox"
      {"validation", _} -> "validation"
      {key, _} -> key
    end)
    |> case do
      [] -> "none"
      labels -> Enum.join(labels, ", ")
    end
  end

  def summary(_capabilities), do: "none"

  defp capability(input, camel_key, snake_key) do
    Map.get(input, camel_key) || Map.get(input, snake_key) ||
      Map.get(input, String.to_atom(camel_key)) ||
      Map.get(input, String.to_atom(snake_key))
  end

  defp truthy?(value) when value in [true, "true", "1", 1], do: true
  defp truthy?(_value), do: false
end
