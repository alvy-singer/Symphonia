import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { JSDOM } from "jsdom";
import ts from "typescript";

const require = createRequire(import.meta.url);

async function loadPrivateWorkspaceMarkdown() {
  const source = await readFile(
    new URL("../lib/private-workspace-markdown.ts", import.meta.url),
    "utf8",
  );
  const compiled = ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
      importsNotUsedAsValues: ts.ImportsNotUsedAsValues.Remove,
    },
  });
  const tempDir = await mkdtemp(join(tmpdir(), "symphonia-private-workspace-md-"));
  const outputPath = join(tempDir, "private-workspace-markdown.cjs");
  await writeFile(outputPath, compiled.outputText);
  return require(outputPath);
}

function installDom() {
  const dom = new JSDOM("<!doctype html><html><body><div id=\"editor\"></div></body></html>");
  globalThis.window = dom.window;
  globalThis.document = dom.window.document;
  Object.defineProperty(globalThis, "navigator", {
    value: dom.window.navigator,
    configurable: true,
  });
  globalThis.MutationObserver = dom.window.MutationObserver;
  globalThis.Event = dom.window.Event;
  globalThis.CustomEvent = dom.window.CustomEvent;
  globalThis.getSelection = dom.window.getSelection.bind(dom.window);
  globalThis.addEventListener = dom.window.addEventListener.bind(dom.window);
  globalThis.removeEventListener = dom.window.removeEventListener.bind(dom.window);
  globalThis.dispatchEvent = dom.window.dispatchEvent.bind(dom.window);
  return dom.window.document.getElementById("editor");
}

async function createMilkdownRoundTrip(root, normalizeMilkdownMarkdown) {
  const { Editor, parserCtx, remarkStringifyOptionsCtx, rootCtx, serializerCtx } =
    await import("@milkdown/kit/core");
  const { commonmark } = await import("@milkdown/kit/preset/commonmark");
  const { gfm } = await import("@milkdown/kit/preset/gfm");

  const editor = await Editor.make()
    .config((ctx) => {
      ctx.set(rootCtx, root);
      ctx.update(remarkStringifyOptionsCtx, (prev) => ({
        ...prev,
        bullet: "-",
        fences: true,
        incrementListMarker: false,
      }));
    })
    .use(commonmark)
    .use(gfm)
    .create();

  const parser = editor.action((ctx) => ctx.get(parserCtx));
  const serializer = editor.action((ctx) => ctx.get(serializerCtx));

  return {
    roundTrip(markdown) {
      return normalizeMilkdownMarkdown(serializer(parser(markdown)));
    },
    destroy() {
      return editor.destroy();
    },
  };
}

test("private workspace Markdown helpers split frontmatter and expose required slash commands", async () => {
  const {
    PRIVATE_WORKSPACE_SLASH_COMMANDS,
    composeWithLegacyFrontmatter,
    restoreArtifactReferenceSyntax,
    splitLegacyFrontmatter,
  } = await loadPrivateWorkspaceMarkdown();

  const markdown = "---\ntitle: Legacy\nstatus: approved\n---\n\n# Body\n";
  const split = splitLegacyFrontmatter(markdown);

  assert.equal(split.frontmatter, "---\ntitle: Legacy\nstatus: approved\n---\n\n");
  assert.equal(split.body, "# Body\n");
  assert.equal(composeWithLegacyFrontmatter(split.frontmatter, split.body), markdown);
  assert.equal(
    restoreArtifactReferenceSyntax("\\[\\[decision-001]] \\[\\[evidence:validation_excerpt:id]]"),
    "[[decision-001]] [[evidence:validation_excerpt:id]]",
  );

  const commandIds = PRIVATE_WORKSPACE_SLASH_COMMANDS.map((command) => command.id).sort();
  assert.deepEqual(commandIds, [
    "artifact-link",
    "blockquote",
    "body-text",
    "bold",
    "bullet-list",
    "callout",
    "code-block",
    "decision-note",
    "evidence-ref",
    "heading",
    "italic",
    "link",
    "numbered-list",
    "run-summary",
    "subtitle",
    "table",
    "task-list",
    "title",
  ]);

  const labels = PRIVATE_WORKSPACE_SLASH_COMMANDS.map((command) => command.label);
  assert.ok(labels.includes("Title"));
  assert.ok(labels.includes("Subtitle"));
  assert.ok(labels.includes("Body text"));

  const subtitleCommand = PRIVATE_WORKSPACE_SLASH_COMMANDS.find(
    (command) => command.id === "subtitle",
  );
  assert.equal(subtitleCommand.markdown, "## Subtitle\n\n");
});

test("Milkdown round-trips private workspace Markdown fixtures without losing required shapes", async () => {
  const {
    composeWithLegacyFrontmatter,
    normalizeMilkdownMarkdown,
    splitLegacyFrontmatter,
  } = await loadPrivateWorkspaceMarkdown();
  const root = installDom();
  const milkdown = await createMilkdownRoundTrip(root, normalizeMilkdownMarkdown);

  try {
    const fixtures = [
      {
        name: "normal markdown",
        markdown:
          "# Heading\n\nParagraph with [link](https://example.com).\n\n> Quoted context\n\n- Parent\n  - Nested\n\n1. First\n2. Second\n",
        includes: ["# Heading", "[link](https://example.com)", "> Quoted context", "Nested"],
      },
      {
        name: "gfm blocks",
        markdown:
          "## Checklist\n\n- [ ] Draft\n- [x] Reviewed\n\n| Item | Status |\n| --- | --- |\n| Plan | Ready |\n\n```ts\nconst value = 1;\n```\n",
        includes: ["- [ ] Draft", "- [x] Reviewed", "| Item | Status |", "```ts", "const value = 1;"],
      },
      {
        name: "artifact references",
        markdown:
          "Linked artifacts: [[decision-001]], [[milestone-001]], [[evidence:validation_excerpt:id]].\n",
        includes: ["[[decision-001]]", "[[milestone-001]]", "[[evidence:validation_excerpt:id]]"],
      },
    ];

    for (const fixture of fixtures) {
      const once = milkdown.roundTrip(fixture.markdown);
      const twice = milkdown.roundTrip(once);

      assert.equal(twice, once, `${fixture.name} should be idempotent after one Milkdown pass`);
      for (const expected of fixture.includes) {
        assert.match(once, escapeRegExp(expected), `${fixture.name} should include ${expected}`);
      }
      assert.doesNotMatch(once, /\\\[\\\[/, `${fixture.name} should not save escaped artifact refs`);
    }

    const legacy = "---\ntitle: Legacy\nstatus: approved\n---\n\n# Legacy body\n\n[[decision-001]]\n";
    const split = splitLegacyFrontmatter(legacy);
    const serializedBody = milkdown.roundTrip(split.body);
    const combined = composeWithLegacyFrontmatter(split.frontmatter, serializedBody);

    assert.ok(combined.startsWith(split.frontmatter));
    assert.match(combined, /# Legacy body/);
    assert.match(combined, /\[\[decision-001\]\]/);
  } finally {
    await milkdown.destroy();
  }
});

function escapeRegExp(value) {
  return new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
}
