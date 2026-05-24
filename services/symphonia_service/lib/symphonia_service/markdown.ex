defmodule SymphoniaService.Markdown do
  @moduledoc """
  Small YAML-frontmatter parser/serializer for the task schema.

  It supports the subset used by Symphonia task files:

  - scalar `key: value`
  - blank scalar `key:`
  - list values:

      files_changed:
        - app/page.tsx
  """

  @ordered_keys [
    "key",
    "title",
    "status",
    "priority",
    "project",
    "assistant",
    "paused_reason",
    "paused_explanation",
    "github_issue",
    "github_issue_state",
    "github_pr",
    "github_pr_state",
    "github_sync_enabled",
    "review_approved",
    "review_summary",
    "files_changed",
    "next_review_action",
    "updated_at"
  ]

  def parse(text) when is_binary(text) do
    case String.split(text, "---\n", parts: 3) do
      ["", frontmatter, body] ->
        %{frontmatter: parse_frontmatter(frontmatter), body: body}

      _ ->
        %{frontmatter: %{}, body: text}
    end
  end

  def serialize(frontmatter, body) when is_map(frontmatter) and is_binary(body) do
    keys =
      @ordered_keys ++
        (frontmatter
         |> Map.keys()
         |> Enum.reject(&(&1 in @ordered_keys))
         |> Enum.sort())

    rendered =
      keys
      |> Enum.filter(&Map.has_key?(frontmatter, &1))
      |> Enum.map(&render_entry(&1, Map.get(frontmatter, &1)))
      |> Enum.join("\n")

    "---\n" <> rendered <> "\n---\n\n" <> String.trim_leading(body)
  end

  defp parse_frontmatter(text) do
    text
    |> String.split("\n")
    |> parse_lines(%{}, nil)
  end

  defp parse_lines([], acc, _current_list), do: acc

  defp parse_lines([line | rest], acc, current_list) do
    cond do
      String.trim(line) == "" ->
        parse_lines(rest, acc, current_list)

      String.starts_with?(String.trim_leading(line), "- ") and current_list ->
        value = line |> String.trim() |> String.trim_leading("- ") |> parse_scalar()
        parse_lines(rest, Map.update!(acc, current_list, &(&1 ++ [value])), current_list)

      true ->
        case String.split(line, ":", parts: 2) do
          [key, value] ->
            key = String.trim(key)
            value = String.trim(value)

            if value == "" and next_line_is_list?(rest) do
              parse_lines(rest, Map.put(acc, key, []), key)
            else
              parse_lines(rest, Map.put(acc, key, parse_scalar(value)), nil)
            end

          _ ->
            parse_lines(rest, acc, nil)
        end
    end
  end

  defp next_line_is_list?([line | _rest]) do
    line |> String.trim_leading() |> String.starts_with?("- ")
  end

  defp next_line_is_list?([]), do: false

  defp parse_scalar(""), do: nil
  defp parse_scalar("true"), do: true
  defp parse_scalar("false"), do: false

  defp parse_scalar(value) do
    value
    |> String.trim()
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
  end

  defp render_entry(key, values) when is_list(values) do
    if Enum.empty?(values) do
      "#{key}:"
    else
      [key <> ":" | Enum.map(values, &"  - #{format_scalar(&1)}")]
      |> Enum.join("\n")
    end
  end

  defp render_entry(key, value), do: "#{key}: #{format_scalar(value)}"

  defp format_scalar(nil), do: ""
  defp format_scalar(true), do: "true"
  defp format_scalar(false), do: "false"
  defp format_scalar(value), do: to_string(value)
end
