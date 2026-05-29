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

const require = createRequire(import.meta.url);
const {
  activeRunPollingTarget,
  automationLabel,
  compactRunBadge,
  canOpenPullRequest,
  canRequestChanges,
  daemonLabel,
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
  runTimelineForTask,
  safeReviewBranch,
  safeSummaryPath,
  taskOperationalBadge,
  terminalRunStateLabel,
  hasFailedRequiredValidation,
  validationBadgeForTask,
  validationSummaryLabel,
  validationSummaryState,
} = require(compiledPath);

const {
  groupReadinessChecks,
  readinessBlocksAutomation,
  readinessPrimaryAction,
  readinessSummary,
  readinessTone,
} = require(readinessCompiledPath);

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
  assert.match(readinessView, /Repository readiness/);
  assert.match(readinessView, /Scanner advisory/);
  assert.doesNotMatch(readinessView, /workspacePath|codexThreadId|turnId|threadId|raw_log|provider_output/);
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
