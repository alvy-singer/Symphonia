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

const readinessSource = await readFile(
  new URL("../lib/readiness-ui-model.ts", import.meta.url),
  "utf8",
);
const readinessCompiled = ts.transpileModule(readinessSource, {
  compilerOptions: {
    module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2022,
    importsNotUsedAsValues: ts.ImportsNotUsedAsValues.Remove,
  },
});
const readinessCompiledPath = join(tempDir, "readiness-ui-model.cjs");
await writeFile(readinessCompiledPath, readinessCompiled.outputText);

const providerSource = await readFile(
  new URL("../lib/provider-ui-model.ts", import.meta.url),
  "utf8",
);
const providerCompiled = ts.transpileModule(providerSource, {
  compilerOptions: {
    module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2022,
    importsNotUsedAsValues: ts.ImportsNotUsedAsValues.Remove,
  },
});
const providerCompiledPath = join(tempDir, "provider-ui-model.cjs");
await writeFile(providerCompiledPath, providerCompiled.outputText);

const accessSource = await readFile(new URL("../lib/access-ui-model.ts", import.meta.url), "utf8");
const accessCompiled = ts.transpileModule(accessSource, {
  compilerOptions: {
    module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2022,
    importsNotUsedAsValues: ts.ImportsNotUsedAsValues.Remove,
  },
});
const accessCompiledPath = join(tempDir, "access-ui-model.cjs");
await writeFile(accessCompiledPath, accessCompiled.outputText);

const runnerSource = await readFile(new URL("../lib/runner-model.ts", import.meta.url), "utf8");
const runnerCompiled = ts.transpileModule(runnerSource, {
  compilerOptions: {
    module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2022,
    importsNotUsedAsValues: ts.ImportsNotUsedAsValues.Remove,
  },
});
const runnerCompiledPath = join(tempDir, "runner-model.cjs");
await writeFile(runnerCompiledPath, runnerCompiled.outputText);

const sandboxSource = await readFile(
  new URL("../lib/sandbox-ui-model.ts", import.meta.url),
  "utf8",
);
const sandboxCompiled = ts.transpileModule(sandboxSource, {
  compilerOptions: {
    module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2022,
    importsNotUsedAsValues: ts.ImportsNotUsedAsValues.Remove,
  },
});
const sandboxCompiledPath = join(tempDir, "sandbox-ui-model.cjs");
await writeFile(sandboxCompiledPath, sandboxCompiled.outputText);

const require = createRequire(import.meta.url);
const {
  activeRunPollingTarget,
  automationLabel,
  compactRunBadge,
  canOpenPullRequest,
  canRequestChanges,
  daemonLabel,
  executionModeLabel,
  harnessLabel,
  harnessStatusLabel,
  harnessStatusForTask,
  groupHarnessDecisions,
  isReviewReady,
  prStateLabel,
  reviewHandoffForTask,
  reviewGateLabel,
  reviewGateState,
  reviewGateTone,
  reviewPrimaryAction,
  runDisplayForTask,
  runOriginLabel,
  runProviderLabel,
  runTimelineForTask,
  safeReviewBranch,
  safeSummaryPath,
  taskOperationalBadge,
  terminalRunStateLabel,
  hasFailedRequiredValidation,
  validationBadgeForTask,
  validationSummaryLabel,
  validationSummaryState,
  workspaceProviderLabel,
} = require(compiledPath);

const {
  groupReadinessChecks,
  readinessBlocksAutomation,
  readinessPrimaryAction,
  readinessSummary,
  readinessTone,
} = require(readinessCompiledPath);

const {
  canHarnessRunProvider,
  providerMissingCapabilityLabels,
  providerStatusLabel,
  providerStatusTone,
} = require(providerCompiledPath);

const {
  canAccess,
  disabledReason,
  permissionSummary,
  roleLabel,
} = require(accessCompiledPath);

const {
  canSelectRunnerForHarness,
  runnerCapabilitySummary,
  runnerCapacityLabel,
  runnerStatusLabel,
  runnerStatusTone,
  runnerTrustDetail,
} = require(runnerCompiledPath);

const {
  sandboxCleanupLabel,
  sandboxSmokeLabel,
  sandboxSmokeTone,
} = require(sandboxCompiledPath);

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
  assert.equal(harnessStatusLabel({ online: true, running: true }), "Running");
  assert.equal(harnessStatusLabel({ online: true, running: true, paused: true }), "Paused");
  assert.equal(harnessStatusLabel({ lastError: { message: "Nope" } }), "Error");
  assert.equal(harnessStatusLabel(null), "Loading");

  assert.deepEqual(
    groupHarnessDecisions([
      { kind: "dispatch", code: "dispatched" },
      { kind: "retry", code: "retry_dispatched" },
      { dispatched: false, code: "status_not_todo" },
    ]),
    {
      dispatch: [{ kind: "dispatch", code: "dispatched" }],
      skip: [{ dispatched: false, code: "status_not_todo" }],
      error: [],
      reconcile: [],
      retry: [{ kind: "retry", code: "retry_dispatched" }],
      pause: [],
    },
  );
});

test("sandbox operations labels stay public-safe", () => {
  assert.equal(sandboxSmokeLabel({ lastSmokeStatus: "passed" }), "Smoke passed");
  assert.equal(sandboxSmokeTone({ lastSmokeStatus: "passed" }), "ready");
  assert.equal(sandboxSmokeLabel({ lastSmokeStatus: "failed" }), "Smoke failed");
  assert.equal(sandboxSmokeTone({ lastSmokeStatus: "failed" }), "warning");
  assert.equal(sandboxSmokeLabel({ lastSmokeStatus: "never_run" }), "Smoke never run");
  assert.equal(sandboxSmokeTone({ lastSmokeStatus: "never_run" }), "neutral");
  assert.equal(sandboxCleanupLabel({ cleanupWarning: true }), "Cleanup warning");
  assert.equal(sandboxCleanupLabel({ cleanupWarning: false }), "Cleanup clear");
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
  assert.equal(
    workspaceProviderLabel({
      id: "run-1",
      state: "completed",
      workspaceProvider: "cloud_sandbox",
    }),
    "Cloud sandbox",
  );
  assert.equal(
    executionModeLabel({
      id: "run-1",
      state: "running",
      executionMode: "cloud_sandbox",
    }),
    "Cloud sandbox",
  );
  assert.equal(
    workspaceProviderLabel({
      id: "run-1",
      state: "completed",
      workspaceProvider: "experimental_sandbox",
    }),
    "Experimental sandbox",
  );
  assert.equal(
    workspaceProviderLabel({ id: "run-1", state: "completed", workspaceProvider: "sandbox_123" }),
    "Local workspace",
  );

  assert.deepEqual(compactRunBadge({ id: "run-1", state: "running" }), {
    label: "Working",
    tone: "neutral",
  });
  assert.deepEqual(
    compactRunBadge({ id: "run-1", state: "running", displayStep: "Running Codex in sandbox" }),
    { label: "Running in sandbox", tone: "neutral" },
  );
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

test("review gate helpers derive review state and safe actions from public task fields", () => {
  const handoff = {
    summary: "Ready",
    filesChanged: ["app/page.tsx"],
    headBranch: "symphonia/task/sym-1",
    baseBranch: "main",
  };

  const needsReview = task({ status: "in_review", handoff });
  assert.equal(reviewGateState(needsReview), "needs_review");
  assert.equal(reviewGateLabel(needsReview), "Needs review");
  assert.equal(reviewGateTone(reviewGateState(needsReview)), "neutral");
  assert.equal(reviewPrimaryAction(needsReview), "approve");
  assert.equal(canOpenPullRequest(needsReview), false);
  assert.equal(canRequestChanges(needsReview), true);

  const approved = task({ status: "in_review", handoff, reviewApproved: true });
  assert.equal(reviewGateState(approved), "approved_ready_for_pr");
  assert.equal(reviewGateLabel(approved), "Approved - ready to open PR");
  assert.equal(reviewGateTone(reviewGateState(approved)), "ready");
  assert.equal(reviewPrimaryAction(approved), "open_pr");
  assert.equal(canOpenPullRequest(approved), true);
  assert.equal(canRequestChanges(approved), true);

  const prOpen = task({
    status: "in_review",
    handoff,
    reviewApproved: true,
    githubPr: "https://github.com/agora-creations/symphonia/pull/1",
    githubPrState: "open",
  });
  assert.equal(reviewGateState(prOpen), "pr_open");
  assert.equal(reviewPrimaryAction(prOpen), "refresh_pr");
  assert.equal(canOpenPullRequest(prOpen), false);
  assert.equal(canRequestChanges(prOpen), false);
  assert.equal(prStateLabel(prOpen), "Open");

  const merged = task({
    status: "completed",
    handoff,
    githubPr: "https://github.com/agora-creations/symphonia/pull/1",
    githubPrState: "merged",
  });
  assert.equal(reviewGateState(merged), "pr_merged");
  assert.equal(reviewGateLabel(merged), "PR merged - completed");
  assert.equal(reviewPrimaryAction(merged), "view_pr");
  assert.equal(prStateLabel(merged), "Merged");

  const closed = task({
    status: "in_review",
    handoff,
    githubPr: "https://github.com/agora-creations/symphonia/pull/1",
    githubPrState: "closed",
  });
  assert.equal(reviewGateState(closed), "pr_closed");
  assert.equal(reviewGateTone(reviewGateState(closed)), "warning");
  assert.equal(reviewPrimaryAction(closed), "request_changes");
  assert.equal(prStateLabel(closed), "Closed without merge");

  assert.equal(
    reviewGateState(
      task({
        status: "in_progress",
        run: { id: "run-1", state: "running", kind: "review_continuation" },
      }),
    ),
    "changes_requested",
  );
  assert.equal(reviewGateState(task({ status: "todo" })), "not_reviewable");
});

test("validation summary helpers derive compact review evidence states", () => {
  const handoff = {
    summary: "Ready",
    filesChanged: ["app/page.tsx"],
    validationEvidence: [],
  };

  assert.equal(validationSummaryState(task({ status: "todo" })), "unknown");
  assert.equal(validationSummaryState(task({ status: "in_review", handoff })), "missing");
  assert.equal(validationSummaryLabel(task({ status: "in_review", handoff })), "Validation missing");
  assert.deepEqual(validationBadgeForTask(task({ status: "in_review", handoff })), {
    label: "Validation missing",
    tone: "neutral",
  });

  const notRun = task({
    status: "in_review",
    handoff: {
      ...handoff,
      validationEvidence: [
        {
          label: "Machine validation",
          status: "not_run",
          detail: "No machine validation command was configured.",
        },
      ],
    },
  });
  assert.equal(validationSummaryState(notRun), "not_run");
  assert.equal(validationSummaryLabel(notRun), "Validation missing");

  const failed = task({
    status: "in_review",
    handoff: {
      ...handoff,
      validationEvidence: [
        {
          label: "Tests",
          status: "failed",
          detail: "Tests failed. Review the private run output locally.",
        },
      ],
    },
  });
  assert.equal(validationSummaryState(failed), "failed");
  assert.equal(validationSummaryLabel(failed), "Validation failed");
  assert.equal(hasFailedRequiredValidation(failed), true);
  assert.deepEqual(validationBadgeForTask(failed), {
    label: "Validation failed",
    tone: "warning",
  });

  const passed = task({
    status: "in_review",
    handoff: {
      ...handoff,
      validationEvidence: [
        { label: "Typecheck", status: "passed", detail: "Typecheck passed." },
      ],
    },
  });
  assert.equal(validationSummaryState(passed), "passed");
  assert.equal(validationSummaryLabel(passed), "Validation passed");
  assert.equal(hasFailedRequiredValidation(passed), false);
  assert.equal(validationBadgeForTask(passed), null);
});

test("operational badges expose sparse Harness reliability states", () => {
  assert.deepEqual(
    taskOperationalBadge(
      task({
        status: "paused",
        pausedReason: "waiting_for_sync",
        pausedExplanation: "Transient Codex App Server error. Retry scheduled in 30 seconds.",
        run: {
          id: "run-1",
          state: "failed",
          retryAt: "2026-05-29T12:00:00Z",
          failureClass: "transient_provider",
        },
      }),
    ),
    {
      label: "Retry scheduled",
      tone: "neutral",
      reason: "2026-05-29T12:00:00Z",
    },
  );

  assert.deepEqual(
    taskOperationalBadge(
      task({
        status: "paused",
        pausedReason: "run_failed",
        pausedExplanation: "Run was marked failed because it stopped updating.",
      }),
    ),
    {
      label: "Run stale",
      tone: "warning",
      reason: "Run was marked failed because it stopped updating.",
    },
  );

  assert.deepEqual(
    taskOperationalBadge(task({ status: "paused", pausedReason: "blocked_by_setup" })),
    { label: "Setup blocked", tone: "warning", reason: undefined },
  );

  assert.deepEqual(
    taskOperationalBadge(
      task({
        status: "paused",
        pausedReason: "run_failed",
        pausedExplanation: "The Coding Assistant did not produce any files that can be reviewed.",
      }),
    ),
    {
      label: "No reviewable files",
      tone: "warning",
      reason: "The Coding Assistant did not produce any files that can be reviewed.",
    },
  );

  assert.deepEqual(taskOperationalBadge(task(), { paused: true }), {
    label: "Automation paused",
    tone: "neutral",
  });
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
  assert.match(taskPage, /Review Decision/);
  assert.match(taskPage, /Pull Request/);
  assert.match(taskPage, /Origin/);
  assert.match(taskPage, /Workspace/);
  assert.match(taskPage, /workspaceProviderLabel/);
  assert.match(taskPage, /Why it started/);
  assert.match(taskPage, /Current state/);
  assert.match(taskPage, /Harness state/);
  assert.match(taskPage, /Retry scheduled\. Harness will retry this task/);
  assert.match(taskPage, /Review branch/);
  assert.match(taskPage, /Curated summary/);
  assert.match(taskPage, /Proof needed/);
  assert.match(taskPage, /Changed files/);
  assert.match(taskPage, /Validation evidence/);
  assert.match(taskPage, /Next action/);
  assert.match(taskPage, /Required validation failed/);
  assert.match(taskPage, /requesting changes is\s+recommended/);
  assert.match(taskPage, /No automatic merge will happen/);
  assert.match(taskPage, /Symphonia will not merge it automatically/);
  assert.match(taskPage, /Base branch/);
  assert.match(taskPage, /Head branch/);
  assert.match(taskPage, /Changed files/);
  assert.match(taskPage, /Request changes on the PR, or close the PR before continuing in Symphonia/);
  assert.match(taskPage, /Codex is continuing the task/);
  assert.match(taskPage, /Codex will continue from this review note/);
  assert.match(taskPage, /Codex ran, but no reviewable files were produced/);
  assert.doesNotMatch(taskPage, /task\.run\.provider/);
  assert.doesNotMatch(taskPage, /task\.run\.workspacePath/);
  assert.doesNotMatch(taskPage, /sandbox_id|sandboxPath|sandboxUrl|sandbox_events/);
  assert.doesNotMatch(taskPage, /task\.run\.codexThreadId/);
  assert.doesNotMatch(taskPage, /event\.threadId/);
  assert.doesNotMatch(taskPage, /event\.turnId/);
});

test("task board uses shared review gate helpers without opening SSE streams", async () => {
  const tasksView = await readFile(new URL("../components/tasks-view.tsx", import.meta.url), "utf8");
  const settingsView = await readFile(new URL("../components/settings-view.tsx", import.meta.url), "utf8");
  const readinessView = await readFile(
    new URL("../components/repository-readiness.tsx", import.meta.url),
    "utf8",
  );
  const repositoryReadiness = await readFile(
    new URL("../services/symphonia_service/lib/symphonia_service/readiness/repository_readiness.ex", import.meta.url),
    "utf8",
  );

  assert.match(tasksView, /reviewGateLabel/);
  assert.match(tasksView, /reviewGateState/);
  assert.match(tasksView, /validationBadgeForTask/);
  assert.match(tasksView, /taskOperationalBadge/);
  assert.match(tasksView, /RepositoryReadinessTaskBanner/);
  assert.doesNotMatch(tasksView, /EventSource/);
  assert.match(settingsView, /Pause Harness/);
  assert.match(settingsView, /Resume Harness/);
  assert.match(settingsView, /Run check now/);
  assert.match(settingsView, /Recent decisions/);
  assert.match(settingsView, /groupHarnessDecisions/);
  assert.match(settingsView, /RepositoryReadinessDetails/);
  assert.match(settingsView, /Coding Assistant Providers/);
  assert.match(settingsView, /ProviderContractRow/);
  assert.match(settingsView, /Not runnable by Harness/);
  assert.match(readinessView, /Repository readiness/);
  assert.match(readinessView, /Scanner advisory/);
  assert.match(repositoryReadiness, /workspace_isolation/);
  assert.doesNotMatch(readinessView, /workspacePath|codexThreadId|turnId|threadId|raw_log|provider_output/);
  assert.doesNotMatch(settingsView, /workspacePath|codexThreadId|turnId|threadId|raw_log|provider_output|transcript/);
});

test("repository readiness helpers prioritize blockers and group checks", () => {
  const readiness = {
    state: "needs_setup",
    summary: "Setup needed",
    nextActions: [],
    checks: [
      {
        id: "validation_policy",
        label: "Validation",
        status: "warning",
        category: "validation",
        detail: "No validation command is configured.",
        action: { id: "configure_validation", label: "Configure validation", href: "/workflow", kind: "navigate" },
      },
      {
        id: "github_linked",
        label: "GitHub linked",
        status: "failed",
        category: "github",
        detail: "Repository is not linked to GitHub.",
        action: { id: "connect_github", label: "Connect GitHub", href: "/settings", kind: "connect" },
      },
      {
        id: "workflow_exists",
        label: "WORKFLOW.md exists",
        status: "failed",
        category: "workspace",
        detail: "WORKFLOW.md is missing.",
        action: { id: "create_workflow", label: "Create WORKFLOW.md", href: "/readiness/workflow/from-template", kind: "create_file" },
      },
    ],
  };

  assert.equal(readinessSummary(readiness), "0 ready · 1 warnings · 2 blocked");
  assert.equal(readinessTone("needs_setup"), "blocked");
  assert.equal(readinessPrimaryAction(readiness).id, "create_workflow");
  assert.equal(groupReadinessChecks(readiness.checks).github[0].id, "github_linked");
  assert.equal(readinessBlocksAutomation(readiness), true);

  const githubBeforeValidation = {
    ...readiness,
    checks: readiness.checks.filter((check) => check.id !== "workflow_exists"),
  };

  assert.equal(readinessPrimaryAction(githubBeforeValidation).id, "connect_github");
});

test("provider helpers label runnable and future providers", () => {
  const codex = {
    id: "codex_app_server",
    label: "Codex App Server",
    configured: true,
    ready: true,
    runnable: true,
    runnableByHarness: true,
    status: "ready",
    reason: "Ready for local Codex runs.",
    capabilities: { context_pack: true, validation_pipeline: true, handoff: true },
    missingCapabilities: [],
  };

  const claude = {
    id: "claude_code",
    label: "Claude Code",
    configured: false,
    ready: false,
    runnable: false,
    runnableByHarness: false,
    status: "experimental",
    reason: "Coming later. Not runnable by Harness V2.",
    capabilities: { validation_pipeline: false, review_branch: false, handoff: false },
    missingCapabilities: ["handoff", "review_branch", "validation_pipeline"],
  };

  assert.equal(canHarnessRunProvider(codex), true);
  assert.equal(providerStatusLabel(codex), "Ready");
  assert.equal(providerStatusTone(codex), "ready");

  const gemini = {
    id: "gemini_cli",
    label: "Gemini CLI",
    configured: true,
    ready: true,
    runnable: true,
    runnableByHarness: false,
    manualOnly: true,
    status: "ready",
    reason: "Manual OpenSandbox runs can use this provider.",
    capabilities: { context_pack: true, validation_pipeline: true, handoff: true },
    missingCapabilities: [],
  };

  assert.equal(canHarnessRunProvider(gemini), false);
  assert.equal(providerStatusLabel(gemini), "Manual only");
  assert.equal(providerStatusTone(gemini), "ready");
  assert.equal(runProviderLabel({ provider: "gemini_cli" }), "Gemini CLI");

  assert.equal(canHarnessRunProvider(claude), false);
  assert.equal(providerStatusLabel(claude), "Coming later");
  assert.deepEqual(providerMissingCapabilityLabels(claude), [
    "handoff",
    "review branch",
    "validation",
  ]);
});

test("access helpers map V1 roles to permissions and disabled copy", () => {
  const viewer = {
    role: "viewer",
    permissions: {
      "repository.view": true,
      "runner.view": true,
      "secret_reference.view": true,
    },
  };
  const reviewer = {
    role: "reviewer",
    permissions: {
      "repository.view": true,
      "review.approve": true,
      "review.request_changes": true,
      "pull_request.refresh": true,
    },
  };
  const operator = {
    role: "operator",
    permissions: {
      "repository.view": true,
      "task.run_codex": true,
      "task.cancel_run": true,
      "harness.pause": true,
    },
  };

  assert.equal(roleLabel("owner"), "Owner");
  assert.equal(
    permissionSummary(viewer),
    "Read-only access to tasks, readiness, handoffs, runs, and activity.",
  );
  assert.equal(canAccess(viewer, "task.run_codex"), false);
  assert.equal(canAccess(viewer, "runner.view"), true);
  assert.equal(canAccess(viewer, "secret_reference.view"), true);
  assert.equal(canAccess(reviewer, "review.approve"), true);
  assert.equal(canAccess(reviewer, "pull_request.open"), false);
  assert.equal(canAccess(operator, "harness.pause"), true);
  assert.equal(canAccess(operator, "runner.use_remote"), false);
  assert.equal(canAccess(operator, "runner.approve"), false);
  assert.equal(canAccess(operator, "sandbox.run"), false);
  assert.equal(canAccess(operator, "review.approve"), false);
  assert.equal(disabledReason(viewer, "task.run_codex"), "You have read-only access.");
  assert.equal(
    disabledReason(reviewer, "pull_request.open"),
    "Reviewers can approve or request changes, but only maintainers and owners can open pull requests.",
  );
  assert.equal(
    disabledReason(operator, "review.approve"),
    "Operators can manage runs and Harness controls, but cannot approve handoffs.",
  );
  assert.equal(
    disabledReason(operator, "runner.use_remote"),
    "Only maintainers and owners can use remote runners when repository policy allows it.",
  );
  assert.equal(
    disabledReason(operator, "sandbox.run"),
    "Only maintainers and owners can run sandbox execution when repository policy allows it.",
  );
});

test("runner UI helpers map status, capacity, and capability summaries", () => {
  const local = {
    id: "local-service",
    name: "Local service",
    mode: "local_service",
    status: "online",
    capabilities: {
      codexAppServer: true,
      localGitWorktree: true,
      experimentalSandbox: false,
      validation: true,
    },
    limits: { maxConcurrentRuns: 1 },
    currentRuns: 0,
  };
  const remote = {
    ...local,
    id: "runner_abc",
    name: "runner-mac-mini",
    mode: "remote_runner",
    status: "online",
    capabilities: {
      codexAppServer: true,
      localGitWorktree: false,
      experimentalSandbox: true,
      validation: true,
    },
  };

  assert.equal(runnerStatusLabel(local), "Online");
  assert.equal(runnerStatusTone(local), "ready");
  assert.equal(runnerCapacityLabel(local), "0 / 1");
  assert.equal(canSelectRunnerForHarness(local), true);

  assert.equal(runnerStatusLabel(remote), "Online · Experimental");
  assert.equal(runnerStatusTone(remote), "warning");
  assert.equal(
    runnerCapabilitySummary(remote),
    "Codex ready · Experimental sandbox · Validation ready",
  );
  assert.equal(canSelectRunnerForHarness(remote), false);
  assert.equal(runnerStatusTone({ ...remote, status: "stale" }), "warning");
  assert.equal(runnerStatusTone({ ...remote, status: "offline" }), "blocked");
  assert.equal(runnerStatusTone({ ...remote, status: "disabled" }), "neutral");
  assert.equal(runnerStatusLabel({ ...remote, trustState: "pending" }), "Pending approval");
  assert.equal(runnerStatusLabel({ ...remote, trustState: "trusted" }), "Trusted · Online");
  assert.equal(runnerStatusLabel({ ...remote, trustState: "revoked" }), "Revoked");
  assert.equal(
    runnerTrustDetail({ ...remote, trustState: "pending" }),
    "Runner is connected but cannot execute until an owner approves it.",
  );
});

test("Next service proxy forwards only safe actor headers", async () => {
  const proxySource = await readFile(
    new URL("../lib/server/symphonia-service.ts", import.meta.url),
    "utf8",
  );

  assert.match(proxySource, /ACTOR_HEADER_NAMES/);
  assert.match(proxySource, /"x-symphonia-actor"/);
  assert.match(proxySource, /"x-symphonia-actor-id"/);
  assert.match(proxySource, /"x-symphonia-role"/);
  assert.match(proxySource, /forwardActorHeaders/);
  assert.doesNotMatch(proxySource, /authorization/i);
  assert.doesNotMatch(proxySource, /cookie/i);
});
