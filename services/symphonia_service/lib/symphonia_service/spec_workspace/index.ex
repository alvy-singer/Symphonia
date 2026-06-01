defmodule SymphoniaService.SpecWorkspace.Index do
  @moduledoc """
  Groups spec artifacts for the repository UI.
  """

  @sections [
    {"Codebase", ["codebase_map", "codebase_conventions", "codebase_architecture"]},
    {"Milestones", ["milestone"]},
    {"Discussions", ["discussion"]},
    {"Requirements", ["requirements"]},
    {"Plans", ["plan"]},
    {"Task proposals", ["task_proposal"]},
    {"Task briefs", ["task_brief"]},
    {"Decisions", ["decision"]}
  ]

  def sections(repository) do
    artifacts = SymphoniaService.SpecWorkspace.list_artifacts(repository)

    Enum.map(@sections, fn {label, types} ->
      section_artifacts =
        types
        |> Enum.flat_map(&Map.get(artifacts, &1, []))
        |> Enum.map(&SymphoniaService.SpecWorkspace.Artifact.summary/1)

      %{
        "label" => label,
        "types" => types,
        "artifacts" => section_artifacts
      }
    end)
  end
end
