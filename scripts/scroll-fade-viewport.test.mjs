import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import ts from "typescript";

const require = createRequire(import.meta.url);
const tempDir = await mkdtemp(join(tmpdir(), "symphonia-scroll-fade-"));

async function compile(
  sourcePath,
  outputName,
  sourceTransform = (source) => source,
  outputTransform = (source) => source,
) {
  const source = sourceTransform(await readFile(new URL(sourcePath, import.meta.url), "utf8"));
  const compiled = ts.transpileModule(source, {
    compilerOptions: {
      esModuleInterop: true,
      jsx: ts.JsxEmit.ReactJSX,
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
    },
  });
  const compiledPath = join(tempDir, outputName);
  await writeFile(compiledPath, outputTransform(compiled.outputText));
  return compiledPath;
}

const modelPath = await compile("../lib/scroll-fade-model.ts", "scroll-fade-model.cjs");
await writeFile(join(tempDir, "utils.cjs"), "exports.cn = (...parts) => parts.filter(Boolean).join(' ');");
const reactPath = require.resolve("react");
const jsxRuntimePath = require.resolve("react/jsx-runtime");
const componentPath = await compile(
  "../components/ui/scroll-fade-viewport.tsx",
  "scroll-fade-viewport.cjs",
  (source) =>
    source
      .replace("@/lib/scroll-fade-model", "./scroll-fade-model.cjs")
      .replace("@/lib/utils", "./utils.cjs"),
  (source) =>
    source
      .replaceAll('require("react")', `require(${JSON.stringify(reactPath)})`)
      .replaceAll(
        'require("react/jsx-runtime")',
        `require(${JSON.stringify(jsxRuntimePath)})`,
      ),
);

const { scrollFadeEdges } = require(modelPath);
const { ScrollFadeViewport } = require(componentPath);
const React = require("react");
const { renderToStaticMarkup } = require("react-dom/server");

test("scroll fade edges respond to horizontal scroll position", () => {
  assert.deepEqual(scrollFadeEdges({ clientWidth: 320, scrollLeft: 0, scrollWidth: 320 }), {
    left: false,
    right: false,
  });
  assert.deepEqual(scrollFadeEdges({ clientWidth: 320, scrollLeft: 0, scrollWidth: 900 }), {
    left: false,
    right: true,
  });
  assert.deepEqual(scrollFadeEdges({ clientWidth: 320, scrollLeft: 120, scrollWidth: 900 }), {
    left: true,
    right: true,
  });
  assert.deepEqual(scrollFadeEdges({ clientWidth: 320, scrollLeft: 580, scrollWidth: 900 }), {
    left: true,
    right: false,
  });
});

test("scroll fade viewport renders children and edge indicators", () => {
  const html = renderToStaticMarkup(
    React.createElement(
      ScrollFadeViewport,
      { className: "flex-1", scrollClassName: "overflow-auto" },
      React.createElement("div", null, "Board columns"),
    ),
  );
  assert.match(html, /Board columns/);
  assert.match(html, /bg-gradient-to-r/);
  assert.match(html, /bg-gradient-to-l/);
});
