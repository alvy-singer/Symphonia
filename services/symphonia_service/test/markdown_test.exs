defmodule SymphoniaService.MarkdownTest do
  use ExUnit.Case, async: true

  alias SymphoniaService.Markdown

  test "parses frontmatter lists and preserves body" do
    text = """
    ---
    key: SYM-1
    title: Parse task
    status: todo
    github_sync_enabled: true
    files_changed:
      - app/page.tsx
      - lib/store.ts
    ---

    # Parse task

    Body stays Markdown.
    """

    parsed = Markdown.parse(text)

    assert parsed.frontmatter["key"] == "SYM-1"
    assert parsed.frontmatter["github_sync_enabled"] == true
    assert parsed.frontmatter["files_changed"] == ["app/page.tsx", "lib/store.ts"]
    assert parsed.body =~ "Body stays Markdown."
  end

  test "serializes ordered frontmatter and body" do
    text =
      Markdown.serialize(
        %{
          "status" => "in_review",
          "key" => "SYM-2",
          "files_changed" => ["a.ts"],
          "title" => "Serialize task"
        },
        "# Serialize task\n"
      )

    assert text =~ "---\nkey: SYM-2\ntitle: Serialize task\nstatus: in_review"
    assert text =~ "files_changed:\n  - a.ts"
    assert text =~ "# Serialize task"
  end

  test "parses and serializes nested GitHub metadata" do
    parsed =
      Markdown.parse("""
      ---
      key: SYM-3
      title: Nested GitHub
      github:
        repo:
          owner: agora-creations
          name: symphonia
        issue:
          number: 123
          state: open
        pull_request:
          number: 456
          state: open
          merged: false
          head_branch: task-branch
          base_branch: main
      ---

      # Nested GitHub
      """)

    assert parsed.frontmatter["github"]["repo"]["owner"] == "agora-creations"
    assert parsed.frontmatter["github"]["issue"]["number"] == 123
    assert parsed.frontmatter["github"]["pull_request"]["merged"] == false

    rendered = Markdown.serialize(parsed.frontmatter, parsed.body)

    assert rendered =~ "github:\n  repo:\n    owner: agora-creations"
    assert rendered =~ "pull_request:\n    number: 456"
    assert rendered =~ "head_branch: task-branch"
  end
end
