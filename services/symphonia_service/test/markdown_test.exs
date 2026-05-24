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
end
