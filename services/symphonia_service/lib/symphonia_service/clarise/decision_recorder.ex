defmodule SymphoniaService.Clarise.DecisionRecorder do
  @moduledoc """
  Records milestone-linked decision artifacts.
  """

  alias SymphoniaService.SpecWorkspace

  def create(repository, milestone, payload) do
    title = string_attr(payload, "title") || "Untitled decision"
    body = string_attr(payload, "body") || default_body(title, milestone)

    decision =
      SpecWorkspace.create_decision(repository, %{
        "title" => title,
        "status" => "approved",
        "related_milestone" => milestone["id"],
        "body" => body
      })

    milestone = link_decision(repository, milestone, decision["id"])
    %{"milestone" => milestone, "decision" => decision}
  end

  defp link_decision(repository, milestone, decision_id) do
    decisions =
      milestone
      |> get_in(["metadata", "decisions"])
      |> List.wrap()
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)
      |> Kernel.++([decision_id])
      |> Enum.uniq()

    SpecWorkspace.update_artifact(repository, "milestone", milestone["id"], %{
      "metadata" => %{"decisions" => decisions}
    })
  end

  defp default_body(title, milestone) do
    """
    # #{title}

    ## Context

    This decision was recorded while establishing #{milestone["id"]}.

    ## Decision

    #{title}

    ## Alternatives considered

    None recorded yet.

    ## Consequences

    This decision is linked to #{milestone["id"]} and should be reviewed with the milestone plan.

    ## Related milestone

    #{milestone["id"]}
    """
  end

  defp string_attr(attrs, key) when is_map(attrs) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: nil, else: value

      _ ->
        nil
    end
  end

  defp string_attr(_attrs, _key), do: nil
end
