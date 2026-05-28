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
  compactRunBadge,
  daemonLabel,
  harnessLabel,
  harnessStatusForTask,
  isReviewReady,
  reviewHandoffForTask,
  runDisplayForTask,
  runOriginLabel,
  runTimelineForTask,
  safeReviewBranch,
  safeSummaryPath,
  terminalRunStateLabel,
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

test("run experience helpers derive public origin, state, and safe paths", () => {
  assert.equal(runOriginLabel({ id: "run-1", kind: "assignment", state: "running" }), "Manual");
  assert.equal(
    runOriginLabel({ id: "run-1", kind: "daemon_assignment", state: "running" }),
    "Harness",
  );
  assert.equal(
    runOriginLabel({ id: "run-1", kind: "review_continuation", state: "running" }),
    "Review continuation",
  );
  assert.equal(runOriginLabel({ id: "run-1", state: "running" }), "Unknown");

  assert.deepEqual(compactRunBadge({ id: "run-1", state: "running" }), {
    label: "Working",
    tone: "neutral",
  });
  assert.deepEqual(
    compactRunBadge({ id: "run-1", state: "running", displayStep: "Checking changes" }),
    { label: "Checking changes", tone: "neutral" },
  );
  assert.deepEqual(compactRunBadge({ id: "run-1", state: "completed" }), {
    label: "Ready for review",
    tone: "ready",
  });
  assert.deepEqual(compactRunBadge({ id: "run-1", state: "failed" }), {
    label: "Failed",
    tone: "warning",
  });
  assert.deepEqual(compactRunBadge({ id: "run-1", state: "canceled" }), {
    label: "Canceled",
    tone: "warning",
  });

  assert.equal(terminalRunStateLabel({ id: "run-1", state: "completed" }), "Completed");
  assert.equal(terminalRunStateLabel({ id: "run-1", state: "running" }), undefined);
  assert.equal(
    isReviewReady(
      task({
        status: "in_review",
        handoff: { summary: "Ready", filesChanged: [] },
      }),
    ),
    true,
  );
  assert.equal(isReviewReady(task({ status: "in_review", handoff: null })), false);
  assert.equal(safeReviewBranch("symphonia/task/sym-1"), "symphonia/task/sym-1");
  assert.equal(safeReviewBranch("/Users/example/private"), undefined);
  assert.equal(safeSummaryPath("symphonia/run-summaries/sym-1.md"), "symphonia/run-summaries/sym-1.md");
  assert.equal(safeSummaryPath("/Users/example/private/summary.md"), undefined);
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
        status: "paused",
        pausedReason: "blocked_by_setup",
        pausedExplanation:
          "Codex is not ready on this machine. Symphonia could not find the managed Codex standalone binary needed to start Codex App Server. Install or repair Codex locally, then retry. No changes were made.",
      }),
    ),
    {
      label: "Blocked",
      reason:
        "Codex is not ready on this machine. Symphonia could not find the managed Codex standalone binary needed to start Codex App Server. Install or repair Codex locally, then retry. No changes were made.",
      tone: "warning",
    },
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
    runDisplayForTask(
      task({
        run: {
          id: "run-1",
          state: "running",
          currentStep: "Preparing Codex App Server thread",
          displayStep: "Starting Codex",
          displayMessage: "Codex is working from the task brief.",
        },
      }),
    ),
    { step: "Starting Codex", message: "Codex is working from the task brief." },
  );

  assert.deepEqual(
    runTimelineForTask(
      task({ run: { id: "run-1", state: "completed", timeline: [{ label: "Local event" }] } }),
      [{ label: "Fetched event", threadId: "thread-1", turnId: "turn-1" }],
    ),
    [{ label: "Fetched event" }],
  );

  assert.deepEqual(
    reviewHandoffForTask(
      task({
        status: "in_review",
        handoff: {
          summary: "Review this branch.",
          filesChanged: [
            "app/file.ts",
            "symphonia/run-summaries/sym-1.md",
            "/Users/example/workspace/app/secret.ts",
          ],
          headBranch: "symphonia/task/sym-1",
          baseBranch: "main",
          curatedSummaryPath: "symphonia/run-summaries/sym-1.md",
          nextReviewAction: "Approve or request changes.",
          validationEvidence: [
            {
              label: "Tests pass",
              status: "not_run",
              detail: "No machine validation evidence was recorded for this expectation.",
            },
          ],
        },
        reviewExpectations: ["Tests pass"],
      }),
    ),
    {
      summary: "Review this branch.",
      files: ["app/file.ts", "symphonia/run-summaries/sym-1.md"],
      nextReviewAction: "Approve or request changes.",
      branch: "symphonia/task/sym-1 -> main",
      curatedSummaryPath: "symphonia/run-summaries/sym-1.md",
      validationEvidence: [
        {
          label: "Tests pass",
          status: "not_run",
          detail: "No machine validation evidence was recorded for this expectation.",
        },
      ],
      proofNeeded: ["Tests pass"],
    },
  );
});

test("task page copy separates Clarise planning from Codex implementation and hides raw run details", async () => {
  const taskPage = await readFile(new URL("../components/task-page.tsx", import.meta.url), "utf8");
  const taskModel = await readFile(new URL("../lib/task-model.ts", import.meta.url), "utf8");
  const runStore = await readFile(
    new URL("../services/symphonia_service/lib/symphonia_service/coding_assistant/run_store.ex", import.meta.url),
    "utf8",
  );

  assert.match(taskModel, /export type CodingAssistantRunKind/);
  assert.match(taskModel, /kind\?: CodingAssistantRunKind/);
  assert.match(runStore, /"kind" => run\["kind"\]/);
  assert.match(taskPage, /Ask Codex to work on this task/);
  assert.match(taskPage, /Codex is working/);
  assert.match(taskPage, /Coding Assistant Run/);
  assert.match(taskPage, /Review Handoff/);
  assert.match(taskPage, /Origin/);
  assert.match(taskPage, /Why it started/);
  assert.match(taskPage, /Current state/);
  assert.match(taskPage, /Review branch/);
  assert.match(taskPage, /Curated summary/);
  assert.match(taskPage, /Proof needed/);
  assert.match(taskPage, /Changed files/);
  assert.match(taskPage, /Validation evidence/);
  assert.match(taskPage, /Next action/);
  assert.match(taskPage, /Codex is continuing the task/);
  assert.match(taskPage, /Codex ran, but no reviewable files were produced/);
  assert.doesNotMatch(taskPage, /task\.run\.provider/);
  assert.doesNotMatch(taskPage, /task\.run\.workspacePath/);
  assert.doesNotMatch(taskPage, /task\.run\.codexThreadId/);
  assert.doesNotMatch(taskPage, /event\.threadId/);
  assert.doesNotMatch(taskPage, /event\.turnId/);
});
