defmodule SymphoniaService.SpecWorkspace.Templates do
  @moduledoc """
  Lightweight Markdown templates for spec workspace artifacts.
  """

  @default_titles %{
    "codebase_map" => "Codebase map",
    "codebase_conventions" => "Codebase conventions",
    "codebase_architecture" => "Codebase architecture",
    "milestone" => "Untitled milestone",
    "discussion" => "Untitled discussion",
    "requirements" => "Untitled requirement",
    "plan" => "Untitled plan",
    "task_proposal" => "Untitled task proposal",
    "task_brief" => "Untitled task brief",
    "decision" => "Untitled decision"
  }

  def title(type), do: Map.fetch!(@default_titles, type)

  def frontmatter(type, id, attrs \\ %{}) do
    now = now()
    attrs = normalize_attrs(attrs)
    title = string_attr(attrs, "title") || title(type)
    status = string_attr(attrs, "status") || "draft"

    extras =
      attrs
      |> Map.drop(["body", "type", "id", "title", "status", "created_at", "updated_at", "source"])
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Map.merge(extras, %{
      "type" => type,
      "id" => id,
      "title" => title,
      "status" => status,
      "created_at" => now,
      "updated_at" => now,
      "source" => string_attr(attrs, "source") || "clarise"
    })
  end

  def body("codebase_map", _id, _attrs) do
    """
    # Codebase Map

    ## Purpose

    ## Entry points

    ## Important paths

    ## Data and state

    ## Open questions
    """
  end

  def body("codebase_conventions", _id, _attrs) do
    """
    # Codebase Conventions

    ## Naming

    ## Formatting

    ## Testing

    ## Review notes
    """
  end

  def body("codebase_architecture", _id, _attrs) do
    """
    # Codebase Architecture

    ## System shape

    ## Boundaries

    ## Key flows

    ## Risks
    """
  end

  def body("milestone", id, attrs) do
    number = suffix_number(id)
    title = string_attr(attrs, "title") || "Untitled"

    """
    # Milestone #{number} — #{title}

    ## Goal

    ## Why this matters

    ## Scope

    ## Non-goals

    ## Acceptance criteria

    ## Open questions

    ## Related artifacts
    """
  end

  def body("discussion", id, attrs) do
    title = string_attr(attrs, "title") || "Untitled discussion"

    """
    # Discussion #{suffix_number(id)} — #{title}

    ## Prompt

    ## Notes

    ## Options

    ## Follow-ups
    """
  end

  def body("requirements", id, attrs) do
    title = string_attr(attrs, "title") || "Untitled requirement"

    """
    # Requirement #{suffix_number(id)} — #{title}

    ## Requirement

    ## Validation criteria

    ## Constraints

    ## Related milestone
    """
  end

  def body("plan", id, attrs) do
    title = string_attr(attrs, "title") || "Untitled plan"

    """
    # Plan #{suffix_number(id)} — #{title}

    ## Objective

    ## Steps

    ## Validation

    ## Risks

    ## Related milestone
    """
  end

  def body("decision", id, attrs) do
    number = suffix_number(id)
    title = string_attr(attrs, "title") || "Untitled"

    """
    # Decision #{number} — #{title}

    ## Context

    ## Decision

    ## Alternatives considered

    ## Consequences

    ## Related milestone
    """
  end

  def body("task_proposal", id, attrs) do
    title = string_attr(attrs, "title") || "Untitled task proposal"

    """
    # #{title}

    ## Summary

    ## Proposed tasks

    ## Related artifacts

    - Proposal: #{id}
    """
  end

  def body("task_brief", id, attrs) do
    title = string_attr(attrs, "title") || "Untitled task brief"

    """
    # #{title}

    ## Goal

    ## Context

    ## Acceptance criteria

    ## Review expectations

    ## Related artifacts

    - Task brief: #{id}
    """
  end

  defp normalize_attrs(attrs) when is_map(attrs) do
    attrs
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp string_attr(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: nil, else: value

      _ ->
        nil
    end
  end

  defp suffix_number(id) do
    case Regex.run(~r/-(\d+)$/, id) do
      [_all, number] -> number
      _ -> "001"
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
