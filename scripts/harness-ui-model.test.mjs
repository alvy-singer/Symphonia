import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import ts from "typescript";

const source = await readFile(new URL("../lib/harness-ui-model.ts", import.meta.url), "utf8");
const compiled = ts.transpileModule(source, {
  compilerOptions: {
    module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2022,
    importsNotUsedAsValues: ts.ImportsNotUsedAsValues.Remove,
  },
});

const tempDir = await mkdtemp(join(tmpdir(), "symphonia-harness-ui-"));
const compiledPath = join(tempDir, "harness-ui-model.cjs");
await writeFile(compiledPath, compiled.outputText);

const require = createRequire(import.meta.url);
const {
  activeRunPollingTarget,
  automationLabel,
  daemonLabel,
  harnessLabel,
  harnessStatusForTask,
  reviewHandoffForTask,
  runTimelineForTask,
} = require(compiledPath);

function task(attrs = {}) {
  return {
    key: "SYM-1",
    title: "Harness task",
    status: "todo",
    priority: "no-priority",
    filesChanged: [],
    repo: "SYM",
    path: "symphonia/tasks/SYM-1.md",
    body: "# Harness task",
    labels: [],
    ...attrs,
  };
}

test("automation and daemon labels reflect enabled and disabled states", () => {
  assert.equal(automationLabel({ enabled: true }), "Automation on");
  assert.equal(automationLabel({ enabled: false }), "Automation off");
  assert.equal(harnessLabel({ enabled: true }), "Automation on");
  assert.equal(harnessLabel({ enabled: false }), "Automation off");
  assert.equal(daemonLabel({ running: true }), "Background service: Active");
  assert.equal(daemonLabel({ running: false }), "Background service: Stopped");
});

test("task badges expose eligibility reasons and active run states", () => {
  assert.deepEqual(
    harnessStatusForTask(
      task(),
      { eligible: true, code: "eligible", reason: "Task is eligible.", checks: [] },
    ),
    { label: "Eligible", reason: "Task is eligible.", tone: "ready" },
  );

  assert.deepEqual(
    harnessStatusForTask(
      task(),
      { eligible: false, code: "automation_disabled", reason: "Automation is disabled.", checks: [] },
    ),
    { label: "Not eligible", reason: "Automation is disabled.", tone: "warning" },
  );

  assert.deepEqual(
    harnessStatusForTask(task({ run: { id: "run-1", state: "queued", currentStep: "Preparing" } })),
    { label: "Queued", reason: "Preparing", tone: "neutral" },
  );

  assert.deepEqual(
    harnessStatusForTask(task({ run: { id: "run-1", state: "running", currentStep: "Executing" } })),
    { label: "Running", reason: "Executing", tone: "neutral" },
  );
});

test("blocked, in-review, polling, timeline, and handoff displays are derived without raw logs", () => {
  assert.deepEqual(
    harnessStatusForTask(
      task({
        status: "paused",
        pausedReason: "run_failed",
        pausedExplanation: "No committable changes.",
      }),
    ),
    { label: "Blocked", reason: "No committable changes.", tone: "warning" },
  );

  assert.deepEqual(
    harnessStatusForTask(
      task({
        status: "in_review",
        handoff: { summary: "Ready", filesChanged: [], headBranch: "symphonia/task/sym-1" },
      }),
    ),
    { label: "In review", reason: "symphonia/task/sym-1", tone: "ready" },
  );

  assert.equal(activeRunPollingTarget(task({ run: { id: "run-1", state: "running" } })), "run-1");
  assert.equal(activeRunPollingTarget(task({ run: { id: "run-1", state: "completed" } })), null);

  assert.deepEqual(
    runTimelineForTask(
      task({ run: { id: "run-1", state: "completed", timeline: [{ label: "Local event" }] } }),
      [{ label: "Fetched event", threadId: "thread-1", turnId: "turn-1" }],
    ),
    [{ label: "Fetched event", threadId: "thread-1", turnId: "turn-1" }],
  );

  assert.deepEqual(
    reviewHandoffForTask(
      task({
        status: "in_review",
        handoff: {
          summary: "Review this branch.",
          filesChanged: ["app/file.ts", "symphonia/run-summaries/sym-1.md"],
          headBranch: "symphonia/task/sym-1",
          baseBranch: "main",
          curatedSummaryPath: "symphonia/run-summaries/sym-1.md",
          nextReviewAction: "Approve or request changes.",
        },
      }),
    ),
    {
      summary: "Review this branch.",
      files: ["app/file.ts", "symphonia/run-summaries/sym-1.md"],
      nextReviewAction: "Approve or request changes.",
      branch: "symphonia/task/sym-1 -> main",
      curatedSummaryPath: "symphonia/run-summaries/sym-1.md",
    },
  );
});
