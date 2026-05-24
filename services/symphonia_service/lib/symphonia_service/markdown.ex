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
    "review_state",
    "next_step",
    "handoff",
    "github",
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

  @nested_orders %{
    "github" => ["repo", "issue", "pull_request"],
    "repo" => ["owner", "name", "url"],
    "issue" => ["owner", "repo", "number", "url", "state"],
    "pull_request" => [
      "owner",
      "repo",
      "number",
      "url",
      "state",
      "merged",
      "head_branch",
      "base_branch"
    ],
    "handoff" => ["head_branch"]
  }

  defp parse_frontmatter(text) do
    text
    |> String.split("\n")
    |> parse_lines(%{}, %{}, nil)
  end

  defp parse_lines([], acc, _paths_by_level, _current_list_path), do: acc

  defp parse_lines([line | rest], acc, paths_by_level, current_list_path) do
    cond do
      String.trim(line) == "" ->
        parse_lines(rest, acc, paths_by_level, current_list_path)

      String.starts_with?(String.trim_leading(line), "- ") and current_list_path ->
        value = line |> String.trim() |> String.trim_leading("- ") |> parse_scalar()
        acc = update_in_path(acc, current_list_path, &(List.wrap(&1) ++ [value]))
        parse_lines(rest, acc, paths_by_level, current_list_path)

      true ->
        case String.split(line, ":", parts: 2) do
          [key, value] ->
            indent = leading_spaces(line)
            level = div(indent, 2)
            key = String.trim(key)
            value = String.trim(value)
            parent_path = if level == 0, do: [], else: Map.get(paths_by_level, level - 1, [])
            path = parent_path ++ [key]
            paths_by_level = Map.put(paths_by_level, level, path)

            cond do
              value != "" ->
                parse_lines(
                  rest,
                  put_in_path(acc, path, parse_scalar(value)),
                  paths_by_level,
                  nil
                )

              next_line_is_list?(rest) ->
                parse_lines(rest, put_in_path(acc, path, []), paths_by_level, path)

              next_line_is_nested?(rest, indent) ->
                parse_lines(rest, put_in_path(acc, path, %{}), paths_by_level, nil)

              true ->
                parse_lines(rest, put_in_path(acc, path, nil), paths_by_level, nil)
            end

          _ ->
            parse_lines(rest, acc, paths_by_level, nil)
        end
    end
  end

  defp next_line_is_list?([line | _rest]) do
    line |> String.trim_leading() |> String.starts_with?("- ")
  end

  defp next_line_is_list?([]), do: false

  defp next_line_is_nested?([line | rest], indent) do
    cond do
      String.trim(line) == "" -> next_line_is_nested?(rest, indent)
      true -> leading_spaces(line) > indent
    end
  end

  defp next_line_is_nested?([], _indent), do: false

  defp parse_scalar(""), do: nil
  defp parse_scalar("true"), do: true
  defp parse_scalar("false"), do: false

  defp parse_scalar(value) do
    value = String.trim(value)

    cond do
      Regex.match?(~r/^\d+$/, value) ->
        String.to_integer(value)

      true ->
        value
        |> String.trim_leading("\"")
        |> String.trim_trailing("\"")
    end
  end

  defp render_entry(key, values) when is_list(values) do
    if Enum.empty?(values) do
      "#{key}:"
    else
      [key <> ":" | Enum.map(values, &"  - #{format_scalar(&1)}")]
      |> Enum.join("\n")
    end
  end

  defp render_entry(key, values) when is_map(values) do
    [key <> ":" | render_map(values, key, 1)]
    |> Enum.join("\n")
  end

  defp render_entry(key, value), do: "#{key}: #{format_scalar(value)}"

  defp render_map(values, parent_key, level) do
    values
    |> ordered_nested_keys(parent_key)
    |> Enum.map(&render_nested_entry(&1, Map.get(values, &1), level))
    |> List.flatten()
  end

  defp render_nested_entry(key, values, level) when is_map(values) do
    [indent(level) <> key <> ":" | render_map(values, key, level + 1)]
  end

  defp render_nested_entry(key, values, level) when is_list(values) do
    prefix = indent(level) <> key <> ":"

    if Enum.empty?(values) do
      prefix
    else
      [prefix | Enum.map(values, &(indent(level + 1) <> "- " <> format_scalar(&1)))]
    end
  end

  defp render_nested_entry(key, value, level) do
    indent(level) <> key <> ": " <> format_scalar(value)
  end

  defp format_scalar(nil), do: ""
  defp format_scalar(true), do: "true"
  defp format_scalar(false), do: "false"
  defp format_scalar(value), do: to_string(value)

  defp ordered_nested_keys(values, parent_key) do
    ordered = Map.get(@nested_orders, parent_key, [])
    extra = values |> Map.keys() |> Enum.reject(&(&1 in ordered)) |> Enum.sort()
    Enum.filter(ordered ++ extra, &Map.has_key?(values, &1))
  end

  defp put_in_path(map, [key], value), do: Map.put(map, key, value)

  defp put_in_path(map, [key | rest], value) do
    child =
      case Map.get(map, key) do
        existing when is_map(existing) -> existing
        _ -> %{}
      end

    Map.put(map, key, put_in_path(child, rest, value))
  end

  defp update_in_path(map, [key], fun), do: Map.update(map, key, fun.(nil), fun)

  defp update_in_path(map, [key | rest], fun) do
    child =
      case Map.get(map, key) do
        existing when is_map(existing) -> existing
        _ -> %{}
      end

    Map.put(map, key, update_in_path(child, rest, fun))
  end

  defp leading_spaces(line),
    do: line |> String.length() |> Kernel.-(String.length(String.trim_leading(line)))

  defp indent(level), do: String.duplicate("  ", level)
end
