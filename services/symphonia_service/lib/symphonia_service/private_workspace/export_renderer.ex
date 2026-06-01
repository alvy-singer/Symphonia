defmodule SymphoniaService.PrivateWorkspace.ExportRenderer do
  @moduledoc """
  Renders public Markdown snapshots from private workspace artifact revisions.
  """

  alias SymphoniaService.{Markdown, PrivateWorkspace}
  alias SymphoniaService.PrivateWorkspace.ExportPolicy

  @private_line_markers [
    "provider_output",
    "provider output",
    "raw_log",
    "raw logs",
    "transcript",
    "thread_id",
    "thread id",
    "turn_id",
    "turn id",
    "sandbox_id",
    "sandbox id",
    "runner_token",
    "runner token",
    "secret_reference",
    "secret reference",
    "evidence_blob",
    "evidence blob",
    "local filesystem"
  ]

  def render(repository, kind, id, revision_id, _opts \\ []) do
    artifact = PrivateWorkspace.read_artifact(repository, kind, id)
    ExportPolicy.validate_exportable!(kind)
    ExportPolicy.validate_revision!(artifact, revision_id)

    body =
      repository
      |> PrivateWorkspace.read_revision(kind, id, revision_id)
      |> sanitize_body()
      |> ensure_heading(artifact)

    Markdown.serialize(
      %{
        "source" => "symphonia",
        "artifact_kind" => kind,
        "exported_at" => now()
      },
      body
    )
  end

  defp ensure_heading(body, artifact) do
    trimmed = String.trim_leading(body)

    if String.starts_with?(trimmed, "#") do
      body
    else
      "# #{public_title(artifact)}\n\n#{body}"
    end
  end

  defp public_title(%{"type" => kind, "title" => title}) do
    "#{kind_label(kind)}: #{sanitize_inline(title || "Untitled")}"
  end

  defp kind_label(kind) do
    kind
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp sanitize_body(body) do
    body
    |> String.split("\n")
    |> Enum.reject(&private_line?/1)
    |> Enum.join("\n")
    |> redact_string()
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp sanitize_inline(value) do
    value
    |> to_string()
    |> redact_string()
    |> String.replace("\n", " ")
    |> String.trim()
  end

  defp private_line?(line) do
    downcased = String.downcase(line)
    Enum.any?(@private_line_markers, &String.contains?(downcased, &1))
  end

  defp redact_string(value) do
    value
    |> String.replace(
      ~r/(^|[\s(])\/(?:Users|private|tmp|var|Volumes|home|opt|usr)\/[^\s),]+/,
      "\\1[local path hidden]"
    )
    |> String.replace(~r/https?:\/\/[^@\s]+@/i, "https://[credential hidden]@")
    |> String.replace(
      ~r/\b[A-Z0-9_]*(TOKEN|SECRET|KEY|PASSWORD)=\S+/i,
      "[environment value hidden]"
    )
    |> String.replace(
      ~r/(sym_pair_|sym_runner_|gh[psoru]_|xox[baprs]-|token=|access_token|secret=|api[_-]?key)/i,
      "[sensitive value hidden]"
    )
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
