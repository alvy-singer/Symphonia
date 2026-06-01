export interface LegacyFrontmatterSplit {
  frontmatter: string | null;
  body: string;
}

export interface PrivateWorkspaceSlashCommand {
  id: string;
  section: "Writing" | "Structure" | "Inline" | "Symphonia";
  label: string;
  description: string;
  markdown: string;
  inline?: boolean;
}

const FRONTMATTER_PATTERN = /^(---[ \t]*\r?\n[\s\S]*?\r?\n---[ \t]*(?:\r?\n){1,2})/;
const ESCAPED_WIKI_REF_PATTERN = /\\\[\\\[([^\]\n]+?)(?:\\\]\\\]|\]\])/g;

export const PRIVATE_WORKSPACE_SLASH_COMMANDS: PrivateWorkspaceSlashCommand[] = [
  {
    id: "title",
    section: "Writing",
    label: "Title",
    description: "Add a top-level document title",
    markdown: "# Title\n\n",
  },
  {
    id: "subtitle",
    section: "Writing",
    label: "Subtitle",
    description: "Add a secondary heading",
    markdown: "## Subtitle\n\n",
  },
  {
    id: "heading",
    section: "Writing",
    label: "Heading",
    description: "Add a section heading",
    markdown: "### Heading\n\n",
  },
  {
    id: "body-text",
    section: "Writing",
    label: "Body text",
    description: "Add a normal paragraph",
    markdown: "Body text\n\n",
  },
  {
    id: "bullet-list",
    section: "Structure",
    label: "Bullet list",
    description: "List unordered items",
    markdown: "- Item\n- Item\n",
  },
  {
    id: "numbered-list",
    section: "Structure",
    label: "Numbered list",
    description: "List ordered steps",
    markdown: "1. First\n2. Second\n",
  },
  {
    id: "task-list",
    section: "Structure",
    label: "Task list",
    description: "Track checklist items",
    markdown: "- [ ] Task\n- [ ] Follow-up\n",
  },
  {
    id: "code-block",
    section: "Structure",
    label: "Code block",
    description: "Insert a fenced code block",
    markdown: "```ts\n// code\n```\n\n",
  },
  {
    id: "table",
    section: "Structure",
    label: "Table",
    description: "Insert a Markdown table",
    markdown: "| Item | Status |\n| --- | --- |\n| Example | Draft |\n\n",
  },
  {
    id: "blockquote",
    section: "Structure",
    label: "Blockquote",
    description: "Quote or indent context",
    markdown: "> Quote\n\n",
  },
  {
    id: "callout",
    section: "Structure",
    label: "Callout",
    description: "Add a highlighted note",
    markdown: "> [!NOTE]\n> Add context here.\n\n",
  },
  {
    id: "bold",
    section: "Inline",
    label: "Bold",
    description: "Emphasize text strongly",
    markdown: "**bold**",
    inline: true,
  },
  {
    id: "italic",
    section: "Inline",
    label: "Italic",
    description: "Emphasize text lightly",
    markdown: "*italic*",
    inline: true,
  },
  {
    id: "link",
    section: "Inline",
    label: "Link",
    description: "Insert a Markdown link",
    markdown: "[label](https://example.com)",
    inline: true,
  },
  {
    id: "artifact-link",
    section: "Symphonia",
    label: "Artifact link",
    description: "Reference a private artifact",
    markdown: "[[decision-001]]",
    inline: true,
  },
  {
    id: "evidence-ref",
    section: "Symphonia",
    label: "Evidence ref",
    description: "Reference private run evidence",
    markdown: "[[evidence:validation_excerpt:id]]",
    inline: true,
  },
  {
    id: "decision-note",
    section: "Symphonia",
    label: "Decision note",
    description: "Capture context and outcome",
    markdown: "## Decision\n\n**Context.** \n\n**Decision.** \n\n**Consequences.** \n\n",
  },
  {
    id: "run-summary",
    section: "Symphonia",
    label: "Run summary section",
    description: "Summarize validation and follow-up",
    markdown: "## Run summary\n\n### Validation\n\n- \n\n### Follow-up\n\n- \n",
  },
];

export function splitLegacyFrontmatter(markdown: string): LegacyFrontmatterSplit {
  const match = FRONTMATTER_PATTERN.exec(markdown);
  if (!match) return { frontmatter: null, body: markdown };

  const frontmatter = match[0] ?? "";
  return {
    frontmatter,
    body: markdown.slice(frontmatter.length),
  };
}

export function composeWithLegacyFrontmatter(
  frontmatter: string | null,
  body: string,
): string {
  if (!frontmatter) return body;
  return `${frontmatter}${body}`;
}

export function restoreArtifactReferenceSyntax(markdown: string): string {
  return markdown.replace(
    ESCAPED_WIKI_REF_PATTERN,
    (_match, reference: string) => `[[${reference.replace(/\\/g, "")}]]`,
  );
}

export function normalizeMilkdownMarkdown(markdown: string): string {
  return restoreArtifactReferenceSyntax(markdown);
}
