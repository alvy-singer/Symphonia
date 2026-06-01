defmodule SymphoniaService.PrivateWorkspace.ExportStatus do
  @moduledoc """
  Derives the public export status shown on private workspace artifacts.
  """

  @statuses ~w(never_exported linked changed_since_export pr_open conflict unlinked)

  def statuses, do: @statuses

  def derive(artifact, exports, fallback_status \\ nil) do
    latest =
      exports
      |> List.wrap()
      |> List.last()

    status =
      case latest do
        nil ->
          fallback_status || "never_exported"

        %{"status" => "unlinked"} ->
          "unlinked"

        %{"status" => "conflict"} ->
          "conflict"

        export ->
          cond do
            present?(export["exported_revision_id"]) and
                export["exported_revision_id"] != artifact["latestRevisionId"] ->
              "changed_since_export"

            export["pull_request_state"] == "open" ->
              "pr_open"

            export["status"] == "pr_open" ->
              "pr_open"

            true ->
              changed_or_linked(artifact, export)
          end
      end

    if status in @statuses, do: status, else: "never_exported"
  end

  defp changed_or_linked(artifact, export) do
    if present?(export["exported_revision_id"]) and
         export["exported_revision_id"] != artifact["latestRevisionId"] do
      "changed_since_export"
    else
      export["status"] || "linked"
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
