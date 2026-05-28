defmodule SymphoniaService.Clarise.ArtifactExtractor do
  @moduledoc """
  Codex-backed Clarise artifact extraction.

  This service is the default extraction path for Clarise chat. It asks local
  Codex App Server for a JSON-only private artifact plan and normalizes the
  response before the web route creates any workspace artifacts.
  """

  alias SymphoniaService.CodingAssistant.AppServerClient

  @kinds ~w(codebase_map milestone requirements plan decision task_brief)

  def extract(repository, payload \\ %{}) do
    messages = normalize_messages(Map.get(payload, "messages", []))
    model_profile = normalize_model_profile(Map.get(payload, "model_profile"))

    case AppServerClient.run_turn(repository["path"], prompt(messages, model_profile),
           sandbox: "read-only",
           timeout_ms: timeout_ms()
         ) do
      {:ok, output} ->
        %{
          "source" => "codex_app_server",
          "plan" => output["last_message"] |> decode_plan!() |> normalize_plan()
        }

      {:error, reason, _events} ->
        raise ArgumentError, "Codex artifact extraction failed: #{reason}"
    end
  end

  defp prompt(messages, model_profile) do
    """
    You are Clarise, Symphonia's private planning assistant.

    Extract private Symphonia workspace artifacts from the conversation below.
    Return only valid JSON. Do not include markdown fences, commentary, or prose
    outside JSON. Do not write files, start task runs, open pull requests, or
    publish evidence.

    JSON schema:
    {
      "assistantText": "short user-facing status text",
      "missingFields": [{"kind": "codebase_map|milestone|requirements|plan|decision|task_brief", "field": "field_name"}],
      "artifactDrafts": [
        {
          "kind": "codebase_map|milestone|requirements|plan|decision|task_brief",
          "title": "artifact title",
          "body": "complete markdown body",
          "metadata": {
            "title": "artifact title",
            "status": "draft",
            "source": "clarise_chat",
            "private": true,
            "provider_created_at": "#{now()}"
          },
          "confirmation": "Created private ...",
          "parentMilestoneId": "optional existing milestone id",
          "linkToBatchMilestone": false
        }
      ]
    }

    Required fields:
    - codebase_map: title
    - milestone: title, goal
    - requirements: title, requirement, milestone unless the same batch creates a milestone
    - plan: title, plan, milestone unless the same batch creates a milestone
    - decision: title, decision, milestone unless the same batch creates a milestone
    - task_brief: title, goal

    Slash command intents:
    - /codebase: create or request fields for a codebase_map.
    - /milestone: create or request fields for a milestone.
    - /requirement: create or request fields for requirements.
    - /plan: create or request fields for a plan.
    - /decision: create or request fields for a decision.
    - /task-brief: create or request fields for a task_brief.
    - /workflow: prepare a private task_brief titled "Set up WORKFLOW.md".
    - /new-project: prepare a batch with milestone title "Project foundation", requirements title "Must-have scope", plan title "Roadmap", and task_brief title "First execution slice".
    - /discuss-phase: prepare a decision titled "Phase implementation decisions".
    - /plan-phase: prepare a plan titled "Phase plan".
    - /execute-phase: prepare a task_brief titled "Phase execution".
    - /verify-work: prepare a task_brief titled "Verification checklist".
    - /ship: prepare a task_brief titled "Ship checklist".
    If a slash command lacks required content, do not expand it into visible template text. Return missingFields.

    Model profile: #{model_profile}
    - budget: keep artifacts concise and prefer one focused next action.
    - balanced: capture enough scope, acceptance criteria, and risks for a useful handoff.
    - quality: include stronger validation, review, risk, and phase-handoff detail.

    Planning loop target:
    - Help the user move through discuss, plan, execute, verify, and ship loops.
    - Prefer codebase_map, milestone, requirements, plan, decision, and task_brief artifacts that make the next action reviewable.
    - Keep implementation work separate; never start a task run, pull request, or GitHub write from chat.

    If required fields are missing, return no artifactDrafts and list missingFields.
    Every artifact is private and must stay in Symphonia workspace artifacts only.

    Conversation JSON:
    #{JSON.encode!(messages)}
    """
  end

  defp decode_plan!(text) when is_binary(text) do
    [text, strip_fence(text), json_object_slice(text)]
    |> Enum.find_value(&decode_object/1)
    |> case do
      nil -> raise ArgumentError, "Codex artifact extraction returned invalid JSON."
      plan -> plan
    end
  end

  defp decode_plan!(_text),
    do: raise(ArgumentError, "Codex artifact extraction returned no JSON.")

  defp decode_object(nil), do: nil

  defp decode_object(candidate) do
    case JSON.decode!(candidate) do
      value when is_map(value) -> value
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp strip_fence(text) do
    text
    |> String.trim()
    |> String.replace(~r/^```(?:json)?\s*/i, "")
    |> String.replace(~r/\s*```$/i, "")
    |> String.trim()
  end

  defp json_object_slice(text) do
    start = :binary.match(text, "{")
    finish = :binary.matches(text, "}") |> List.last()

    case {start, finish} do
      {{start_index, _}, {finish_index, _}} when finish_index > start_index ->
        binary_part(text, start_index, finish_index - start_index + 1)

      _ ->
        nil
    end
  end

  defp normalize_plan(plan) do
    artifact_drafts =
      plan
      |> Map.get("artifactDrafts", [])
      |> List.wrap()
      |> Enum.flat_map(&normalize_artifact_draft/1)

    missing_fields =
      plan
      |> Map.get("missingFields", [])
      |> List.wrap()
      |> Enum.flat_map(&normalize_missing_field/1)

    %{
      "assistantText" =>
        string_attr(plan, "assistantText") || assistant_text(artifact_drafts, missing_fields),
      "artifactDrafts" => artifact_drafts,
      "missingFields" => missing_fields
    }
  end

  defp normalize_artifact_draft(draft) when is_map(draft) do
    kind = string_attr(draft, "kind")
    title = string_attr(draft, "title")
    body = string_attr(draft, "body")
    confirmation = string_attr(draft, "confirmation")

    if kind in @kinds && present?(title) && present?(body) && present?(confirmation) do
      metadata =
        draft
        |> Map.get("metadata", %{})
        |> case do
          value when is_map(value) -> value
          _ -> %{}
        end
        |> Map.merge(%{
          "title" => title,
          "status" => "draft",
          "source" => "clarise_chat",
          "private" => true,
          "provider_created_at" =>
            string_attr(draft["metadata"] || %{}, "provider_created_at") || now()
        })

      [
        %{
          "kind" => kind,
          "title" => title,
          "body" => body,
          "metadata" => metadata,
          "confirmation" => confirmation,
          "parentMilestoneId" => string_attr(draft, "parentMilestoneId"),
          "linkToBatchMilestone" => draft["linkToBatchMilestone"] == true
        }
      ]
    else
      []
    end
  end

  defp normalize_artifact_draft(_draft), do: []

  defp normalize_missing_field(field) when is_map(field) do
    kind = string_attr(field, "kind")
    name = string_attr(field, "field")

    if kind in @kinds && present?(name) do
      [%{"kind" => kind, "field" => name}]
    else
      []
    end
  end

  defp normalize_missing_field(_field), do: []

  defp normalize_messages(messages) when is_list(messages) do
    messages
    |> Enum.flat_map(fn
      %{"role" => role, "content" => content} when role in ["user", "assistant", "clarise"] ->
        content = to_string(content) |> String.trim()
        if content == "", do: [], else: [%{"role" => role, "content" => content}]

      _ ->
        []
    end)
  end

  defp normalize_messages(_messages), do: []

  defp normalize_model_profile(profile) when profile in ["quality", "budget"], do: profile
  defp normalize_model_profile(_profile), do: "balanced"

  defp assistant_text(artifact_drafts, _missing_fields) when length(artifact_drafts) > 1 do
    "Saving #{length(artifact_drafts)} private docs."
  end

  defp assistant_text([draft], _missing_fields), do: "Saving #{draft["kind"]}."

  defp assistant_text(_artifact_drafts, missing_fields) when length(missing_fields) > 0 do
    "Missing fields: " <>
      (missing_fields
       |> Enum.map(fn item -> "#{item["kind"]}: #{item["field"]}" end)
       |> Enum.join("; ")) <> "."
  end

  defp assistant_text(_artifact_drafts, _missing_fields) do
    "I can help run a planning loop by creating private codebase maps, milestones, requirements, plans, decisions, and task briefs."
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
  defp present?(value), do: is_binary(value) && String.trim(value) != ""

  defp timeout_ms do
    case System.get_env("SYMPHONIA_CLARISE_CODEX_TIMEOUT_MS") do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int > 0 -> int
          _ -> 120_000
        end

      _ ->
        120_000
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
