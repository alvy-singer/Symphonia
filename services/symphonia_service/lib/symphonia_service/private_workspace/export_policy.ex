defmodule SymphoniaService.PrivateWorkspace.ExportPolicy do
  @moduledoc """
  Policy checks for manual private workspace exports.
  """

  alias SymphoniaService.GitHub.RepositoryLink

  @exportable_kinds ~w(codebase_map codebase_conventions milestone plan decision run_summary)
  @blocked_prefixes ~w(.git/ .github/workflows/ symphonia/private/ .symphonia/ node_modules/)
  @binary_extensions ~w(
    .7z .avif .bin .bmp .class .dll .dmg .doc .docx .exe .gif .gz .ico .jar .jpeg .jpg
    .mov .mp3 .mp4 .pdf .png .ppt .pptx .rar .so .tar .tiff .webm .webp .xls .xlsx .zip
  )

  def exportable_kinds, do: @exportable_kinds

  def validate_exportable!(kind) when kind in @exportable_kinds, do: :ok

  def validate_exportable!(_kind) do
    raise ArgumentError, "This private workspace artifact type cannot be exported to GitHub."
  end

  def validate_revision!(artifact, revision_id) do
    revisions = artifact["metadata"]["revisions"] |> List.wrap() |> Enum.map(& &1["id"])

    unless revision_id in revisions do
      raise ArgumentError, "Private workspace revision not found."
    end

    :ok
  end

  def github_repo!(repository) do
    case RepositoryLink.link(repository) do
      %{"owner" => owner, "name" => name} = link when is_binary(owner) and is_binary(name) ->
        %{
          "owner" => owner,
          "name" => name,
          "target_repo" => "#{owner}/#{name}",
          "default_branch" => link["defaultBranch"] || link["default_branch"] || "main"
        }

      _ ->
        raise ArgumentError, "Link this local repository to GitHub before exporting artifacts."
    end
  end

  def normalize_target_path!(path) when is_binary(path) do
    path = String.trim(path)

    cond do
      path == "" ->
        raise ArgumentError, "Choose a GitHub target path."

      String.match?(path, ~r/^[A-Za-z]:/) or String.starts_with?(path, "/") ->
        raise ArgumentError, "GitHub target path must be relative."

      String.contains?(path, "\\") ->
        raise ArgumentError, "GitHub target path must use forward slashes."

      true ->
        path
        |> reject_unsafe_segments!()
        |> reject_private_path!()
        |> reject_binary_extension!()
    end
  end

  def normalize_target_path!(_path), do: raise(ArgumentError, "Choose a GitHub target path.")

  def default_target_path(%{"type" => kind, "id" => id, "title" => title}) do
    slug = slug(title || id)

    case kind do
      "codebase_map" -> "docs/symphonia/codebase-map.md"
      "codebase_conventions" -> "docs/symphonia/codebase-conventions.md"
      "milestone" -> "docs/symphonia/milestones/#{slug}.md"
      "plan" -> "docs/symphonia/plans/#{slug}.md"
      "decision" -> "docs/symphonia/decisions/#{slug}.md"
      "run_summary" -> "docs/symphonia/run-summaries/#{slug}.md"
      _ -> "docs/symphonia/#{slug}.md"
    end
  end

  defp reject_unsafe_segments!(path) do
    segments = String.split(path, "/", trim: true)

    if segments == [] or Enum.any?(segments, &(&1 in [".", ".."])) or
         Enum.any?(segments, &String.starts_with?(&1, ".env")) do
      raise ArgumentError, "GitHub target path is not allowed."
    end

    path
  end

  defp reject_private_path!(path) do
    lowered = String.downcase(path)

    if Enum.any?(@blocked_prefixes, &String.starts_with?(lowered, &1)) do
      raise ArgumentError, "GitHub target path is not allowed."
    end

    path
  end

  defp reject_binary_extension!(path) do
    if String.downcase(Path.extname(path)) in @binary_extensions do
      raise ArgumentError, "GitHub target path must be a text Markdown file."
    end

    path
  end

  defp slug(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "artifact"
      slug -> slug
    end
  end
end
