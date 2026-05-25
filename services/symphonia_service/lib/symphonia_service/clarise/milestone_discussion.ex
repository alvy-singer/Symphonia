defmodule SymphoniaService.Clarise.MilestoneDiscussion do
  @moduledoc """
  Deterministic discussion artifact builder for Clarise milestone setup.
  """

  @questions [
    {"accomplish", "What should this milestone accomplish?"},
    {"why", "Why does it matter?"},
    {"include", "What should be included?"},
    {"exclude", "What should be excluded?"},
    {"complete", "What would make this feel complete?"},
    {"codebase", "What parts of the codebase are likely involved?"},
    {"risks", "What risks or unknowns should be tracked?"}
  ]

  def questions, do: @questions

  def body(milestone, payload) do
    title = string_attr(payload, "title") || milestone["title"] || "Untitled milestone"
    goal = string_attr(payload, "goal") || section(milestone["body"], "Goal") || ""
    answers = Map.get(payload, "answers", %{})

    """
    # #{human_id(milestone["id"])} Discussion

    ## User intent

    #{blank_fallback(goal, "No intent has been recorded yet.")}

    ## Clarise questions

    #{question_list()}

    ## User answers

    #{answers_body(answers)}

    ## Decisions discovered

    None recorded yet.

    ## Open questions

    #{open_questions(answers)}

    ## Clarise summary

    Clarise is helping turn "#{title}" into a milestone, requirements, and a plan. The answers above are the source for the next generated artifacts.
    """
  end

  defp question_list do
    @questions
    |> Enum.map(fn {_id, question} -> "- #{question}" end)
    |> Enum.join("\n")
  end

  defp answers_body(answers) when is_map(answers) do
    @questions
    |> Enum.map(fn {id, question} ->
      answer = answers |> Map.get(id, "") |> to_string()
      "### #{question}\n\n#{blank_fallback(answer, "No answer yet.")}"
    end)
    |> Enum.join("\n\n")
  end

  defp answers_body(_answers), do: answers_body(%{})

  defp open_questions(answers) when is_map(answers) do
    unanswered =
      @questions
      |> Enum.reject(fn {id, _question} -> present?(Map.get(answers, id)) end)
      |> Enum.map(fn {_id, question} -> "- #{question}" end)

    case unanswered do
      [] -> "No open discussion questions."
      items -> Enum.join(items, "\n")
    end
  end

  defp open_questions(_answers), do: open_questions(%{})

  defp section(body, heading) when is_binary(body) do
    pattern = ~r/^## #{Regex.escape(heading)}\s*\n(?<content>.*?)(?=^## |\z)/ms

    case Regex.named_captures(pattern, body) do
      %{"content" => content} ->
        content = String.trim(content)
        if content == "", do: nil, else: content

      _ ->
        nil
    end
  end

  defp section(_body, _heading), do: nil

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

  defp blank_fallback(value, fallback) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: fallback, else: value
  end

  defp blank_fallback(_value, fallback), do: fallback

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp human_id("milestone-" <> number), do: "Milestone #{number}"
  defp human_id(id), do: id
end
