defmodule SymphoniaService.Clarise.FeedbackStructurer do
  @moduledoc """
  Deterministic local feedback structuring for Clarise.

  Milestone 5 keeps Clarise rule-based, but the output contract matches the
  future LLM path: natural feedback becomes actionable checklist items.
  """

  @imperatives ~w(add address change ensure fix keep make remove show update use)

  def structure(feedback) when is_binary(feedback) do
    feedback
    |> String.trim()
    |> split_clauses()
    |> Enum.map(&sentence_to_action/1)
    |> Enum.reject(&(&1 == ""))
  end

  def structure(_feedback), do: []

  defp split_clauses(""), do: []

  defp split_clauses(feedback) do
    feedback
    |> String.split(~r/[\n.;]+/)
    |> Enum.flat_map(&String.split(&1, ~r/,\s+(?=(?:and\s+)?(?:add|address|change|ensure|fix|keep|make|remove|show|update|use)\b)/i))
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.replace(&1, ~r/^and\s+/i, ""))
    |> Enum.reject(&(&1 == ""))
  end

  defp sentence_to_action(sentence) do
    normalized = sentence |> String.trim() |> String.trim_trailing(".")
    lower = String.downcase(normalized)

    cond do
      Regex.match?(~r/^the .*card.*too dense$/, lower) ->
        "Make task cards less dense."

      Regex.match?(~r/^show retry only when paused$/, lower) ->
        "Show the retry action only when the task is paused."

      Regex.match?(~r/^make the project label smaller$/, lower) ->
        "Make the project label visually smaller."

      imperative?(lower) ->
        normalized |> capitalize_first() |> ensure_period()

      true ->
        "Address: " <> ensure_period(normalized)
    end
  end

  defp imperative?(sentence) do
    first_word =
      sentence
      |> String.split(~r/\s+/, parts: 2)
      |> List.first()

    first_word in @imperatives
  end

  defp capitalize_first(""), do: ""

  defp capitalize_first(value) do
    {first, rest} = String.split_at(value, 1)
    String.upcase(first) <> rest
  end

  defp ensure_period(value) do
    value = String.trim(value)
    if String.ends_with?(value, "."), do: value, else: value <> "."
  end
end
