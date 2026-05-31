import type {
  CodingAssistantRun,
  CodingAssistantRunEvent,
  ServiceTask,
  TaskEligibilityExplanation,
  ValidationEvidence,
} from "@/lib/task-model";
import type { RepositoryAutomationState } from "@/lib/repository-model";

export interface HarnessStatusBadge {
  label: string;
  reason?: string;
  tone: "ready" | "warning" | "neutral";
}

export type HarnessDecisionKind =
  | "dispatch"
  | "skip"
  | "error"
  | "reconcile"
  | "retry"
  | "pause";

export interface HarnessDecision {
  at?: string;
  repo?: string;
  task?: string;
  code: string;
  kind?: HarnessDecisionKind;
  dispatched?: boolean;
  reason?: string;
  runId?: string;
}

export interface HarnessStatusLike {
  running?: boolean;
  online?: boolean;
  paused?: boolean;
  lastError?: { message?: string } | null;
  recentDecisions?: HarnessDecision[];
}

export interface CompactRunBadge {
  label:
    | "Working"
    | "Running on runner"
    | "Running in sandbox"
    | "Importing patch"
    | "Validating changes"
    | "Checking changes"
    | "Ready for review"
    | "Failed"
    | "Canceled";
  tone: "neutral" | "ready" | "warning";
}

export interface ReviewHandoffView {
  summary?: string;
  files: string[];
  nextReviewAction?: string;
  branch?: string;
  curatedSummaryPath?: string;
  validationEvidence: ValidationEvidence[];
  proofNeeded: string[];
}

export type ReviewGateState =
  | "needs_review"
  | "approved_ready_for_pr"
  | "pr_open"
  | "pr_merged"
  | "pr_closed"
  | "changes_requested"
  | "not_reviewable";

export type ValidationSummaryState =
  | "passed"
  | "failed"
  | "missing"
  | "not_run"
  | "unknown";

export function automationLabel(automation?: RepositoryAutomationState | null): string {
  return automation?.enabled ? "Automation on" : "Automation off";
}

export function harnessLabel(automation?: RepositoryAutomationState | null): string {
  return automation?.enabled ? "Automation on" : "Automation off";
}

export function daemonLabel(daemon?: { running?: boolean } | null): string {
  return daemon?.running ? "Background service: Active" : "Background service: Stopped";
}

export function harnessStatusLabel(status?: HarnessStatusLike | null): string {
  if (!status) return "Loading";
  if (status.lastError?.message) return "Error";
  if (status.paused) return "Paused";
  if (status.online && status.running) return "Running";
  return "Unavailable";
}

export function groupHarnessDecisions(
  decisions: HarnessDecision[] = [],
): Record<HarnessDecisionKind, HarnessDecision[]> {
  const groups: Record<HarnessDecisionKind, HarnessDecision[]> = {
    dispatch: [],
    skip: [],
    error: [],
    reconcile: [],
    retry: [],
    pause: [],
  };

  for (const decision of decisions) {
    const kind = decision.kind ?? (decision.dispatched ? "dispatch" : "skip");
    if (kind in groups) {
      groups[kind as HarnessDecisionKind].push(decision);
    }
  }

  return groups;
}

export function isActiveRun(run?: CodingAssistantRun | null): boolean {
  return run?.state === "queued" || run?.state === "running";
}

export function activeRunPollingTarget(task?: Pick<ServiceTask, "run"> | null): string | null {
  return isActiveRun(task?.run) && task?.run?.id ? task.run.id : null;
}

export function runOriginLabel(run?: CodingAssistantRun | null): string {
  switch (run?.kind) {
    case "assignment":
      return "Manual";
    case "daemon_assignment":
      return "Harness";
    case "review_continuation":
      return "Review continuation";
    default:
      return "Unknown";
  }
}

export function workspaceProviderLabel(run?: CodingAssistantRun | null): string {
  switch (run?.workspaceProvider) {
    case "cloud_sandbox":
      return "Cloud sandbox";
    case "experimental_sandbox":
      return "Experimental sandbox";
    case "local_git_worktree":
    case undefined:
      return "Local workspace";
    default:
      return "Local workspace";
  }
}

export function executionModeLabel(run?: CodingAssistantRun | null): string {
  if (run?.executionMode === "cloud_sandbox" || run?.workspaceProvider === "cloud_sandbox") {
    return "Cloud sandbox";
  }

  return run?.executionMode === "remote" || run?.runner?.mode === "remote_runner"
    ? "Remote"
    : "Local";
}

export function runRunnerLabel(run?: CodingAssistantRun | null): string {
  return run?.runner?.name ?? "Local service";
}

export function runProviderLabel(run?: CodingAssistantRun | null): string {
  switch (run?.provider) {
    case "gemini_cli":
      return "Gemini CLI";
    case "codex_app_server":
      return "Codex App Server";
    case "codex":
      return "Legacy Codex";
    case "local_demo":
      return "Local demo";
    default:
      return run?.provider ?? "Coding Assistant";
  }
}

export function compactRunBadge(run?: CodingAssistantRun | null): CompactRunBadge | null {
  if (!run) return null;

  if (run.state === "completed") return { label: "Ready for review", tone: "ready" };
  if (run.state === "failed") return { label: "Failed", tone: "warning" };
  if (run.state === "canceled") return { label: "Canceled", tone: "warning" };

  const step = run.displayStep ?? run.currentStep ?? "";
  if (step.includes("sandbox") || step.includes("Sandbox")) {
    return { label: "Running in sandbox", tone: "neutral" };
  }
  if (step.includes("runner") || step.includes("Runner")) {
    return { label: "Running on runner", tone: "neutral" };
  }
  if (step.includes("Importing")) {
    return { label: "Importing patch", tone: "neutral" };
  }
  if (step.includes("Validating")) {
    return { label: "Validating changes", tone: "neutral" };
  }
  if (step.includes("Checking") || step.includes("Detecting") || step.includes("Creating")) {
    return { label: "Checking changes", tone: "neutral" };
  }

  return { label: "Working", tone: "neutral" };
}

export function terminalRunStateLabel(run?: CodingAssistantRun | null): string | undefined {
  if (run?.state === "completed") return "Completed";
  if (run?.state === "failed") return "Failed";
  if (run?.state === "canceled") return "Canceled";
  return undefined;
}

export function isReviewReady(task: ServiceTask): boolean {
  return task.status === "in_review" && Boolean(task.handoff);
}

export function reviewGateState(task: ServiceTask): ReviewGateState {
  if (task.status === "completed" && task.githubPrState === "merged") {
    return "pr_merged";
  }

  if (task.status === "in_review" && task.githubPrState === "open") {
    return "pr_open";
  }

  if (task.status === "in_review" && task.githubPrState === "closed") {
    return "pr_closed";
  }

  if (task.status === "in_review" && task.reviewApproved && task.handoff) {
    return "approved_ready_for_pr";
  }

  if (task.status === "in_review" && task.handoff) {
    return "needs_review";
  }

  if (task.status === "in_progress" && task.run?.kind === "review_continuation") {
    return "changes_requested";
  }

  return "not_reviewable";
}

export function reviewGateLabel(task: ServiceTask): string {
  switch (reviewGateState(task)) {
    case "needs_review":
      return "Needs review";
    case "approved_ready_for_pr":
      return "Approved - ready to open PR";
    case "pr_open":
      return "PR open - waiting for merge";
    case "pr_merged":
      return "PR merged - completed";
    case "pr_closed":
      return "PR closed without merge";
    case "changes_requested":
      return "Changes requested - Codex continuing";
    case "not_reviewable":
      return "Not reviewable";
  }
}

export function reviewGateTone(state: ReviewGateState): "neutral" | "ready" | "warning" {
  switch (state) {
    case "approved_ready_for_pr":
    case "pr_merged":
      return "ready";
    case "pr_closed":
      return "warning";
    default:
      return "neutral";
  }
}

export function reviewPrimaryAction(
  task: ServiceTask,
): "approve" | "request_changes" | "open_pr" | "refresh_pr" | "view_pr" | null {
  switch (reviewGateState(task)) {
    case "needs_review":
      return "approve";
    case "approved_ready_for_pr":
      return "open_pr";
    case "pr_open":
      return "refresh_pr";
    case "pr_merged":
      return task.githubPr ? "view_pr" : null;
    case "pr_closed":
      return canRequestChanges(task) ? "request_changes" : task.githubPr ? "view_pr" : null;
    case "changes_requested":
    case "not_reviewable":
      return null;
  }
}

export function canOpenPullRequest(task: ServiceTask): boolean {
  return reviewGateState(task) === "approved_ready_for_pr";
}

export function canRequestChanges(task: ServiceTask): boolean {
  return (
    task.status === "in_review" &&
    Boolean(task.handoff) &&
    task.githubPrState !== "open" &&
    task.githubPrState !== "merged"
  );
}

export function prStateLabel(task: ServiceTask): string | undefined {
  switch (task.githubPrState) {
    case "open":
      return "Open";
    case "merged":
      return "Merged";
    case "closed":
      return "Closed without merge";
    case undefined:
      return undefined;
    default:
      return "Unknown";
  }
}

export function validationSummaryState(task: ServiceTask): ValidationSummaryState {
  if (!task.handoff) return "unknown";

  const evidence = task.handoff.validationEvidence ?? [];
  if (evidence.length === 0) return "missing";
  if (evidence.some((item) => item.status === "failed")) return "failed";
  if (evidence.every((item) => item.status === "passed")) return "passed";
  if (evidence.some((item) => item.status === "not_run")) return "not_run";
  return "unknown";
}

export function validationSummaryLabel(task: ServiceTask): string {
  switch (validationSummaryState(task)) {
    case "passed":
      return "Validation passed";
    case "failed":
      return "Validation failed";
    case "missing":
    case "not_run":
      return "Validation missing";
    case "unknown":
      return "Validation unknown";
  }
}

export function hasFailedRequiredValidation(task: ServiceTask): boolean {
  return validationSummaryState(task) === "failed";
}

export function validationBadgeForTask(
  task: ServiceTask,
): { label: string; tone: "ready" | "warning" | "neutral" } | null {
  const state = validationSummaryState(task);

  if (state === "failed") {
    return { label: "Validation failed", tone: "warning" };
  }

  if (task.status === "in_review" && (state === "missing" || state === "not_run")) {
    return { label: "Validation missing", tone: "neutral" };
  }

  return null;
}

export function taskOperationalBadge(
  task: ServiceTask,
  harnessStatus?: HarnessStatusLike | null,
): { label: string; tone: "ready" | "warning" | "neutral"; reason?: string } | null {
  const explanation = task.pausedExplanation ?? task.run?.message ?? "";

  if (task.pausedReason === "blocked_by_setup") {
    return { label: "Setup blocked", tone: "warning", reason: task.pausedExplanation };
  }

  if (/stopped updating|stale|too long|workspace is missing/i.test(explanation)) {
    return { label: "Run stale", tone: "warning", reason: task.pausedExplanation };
  }

  if (task.pausedReason === "waiting_for_sync" && task.run?.retryAt) {
    return { label: "Retry scheduled", tone: "neutral", reason: task.run.retryAt };
  }

  if (/no reviewable files|did not produce any files/i.test(explanation)) {
    return { label: "No reviewable files", tone: "warning", reason: task.pausedExplanation };
  }

  if (validationSummaryState(task) === "failed") {
    return { label: "Validation failed", tone: "warning" };
  }

  if (harnessStatus?.paused && task.status === "todo") {
    return { label: "Automation paused", tone: "neutral" };
  }

  return null;
}

export function harnessStatusForTask(
  task: ServiceTask,
  eligibility?: TaskEligibilityExplanation,
): HarnessStatusBadge | null {
  if (task.run?.state === "queued") {
    return { label: "Queued", reason: displayProgressStep(task.run), tone: "neutral" };
  }

  if (task.run?.state === "running") {
    return { label: "Running", reason: displayProgressStep(task.run), tone: "neutral" };
  }

  if (task.status === "in_review") {
    return {
      label: "In review",
      reason: safeReviewBranch(task.handoff?.headBranch ?? task.run?.reviewBranch),
      tone: "ready",
    };
  }

  if (task.status === "paused") {
    const waitingForRetry = task.pausedReason === "waiting_for_sync" && task.run?.retryAt;
    const blocked =
      task.pausedReason === "run_failed" || task.pausedReason === "blocked_by_setup";

    return {
      label: waitingForRetry ? "Retry scheduled" : blocked ? "Blocked" : "Paused",
      reason: task.pausedExplanation,
      tone: blocked ? "warning" : "neutral",
    };
  }

  if (task.status === "todo" && eligibility) {
    return eligibility.eligible
      ? { label: "Eligible", reason: eligibility.reason, tone: "ready" }
      : { label: "Not eligible", reason: eligibility.reason, tone: "warning" };
  }

  return null;
}

export function runTimelineForTask(
  task: Pick<ServiceTask, "run">,
  runEvents: CodingAssistantRunEvent[],
): CodingAssistantRunEvent[] {
  const events = runEvents.length > 0 ? runEvents : (task.run?.timeline ?? []);

  return events.map((event) => ({
    ...(event.id ? { id: event.id } : {}),
    ...(event.at || event.updatedAt ? { at: event.at ?? event.updatedAt } : {}),
    ...(event.label || event.displayStep ? { label: event.label ?? event.displayStep } : {}),
  }));
}

export function reviewHandoffForTask(task: ServiceTask): ReviewHandoffView {
  const summary = redactUnsafeText(task.handoff?.summary ?? task.reviewSummary);
  const files =
    task.handoff && task.handoff.filesChanged.length > 0
      ? task.handoff.filesChanged
      : task.filesChanged;
  const nextReviewAction = redactUnsafeText(
    task.handoff?.nextReviewAction ?? task.nextReviewAction,
  );
  const headBranch = safeReviewBranch(task.handoff?.headBranch);
  const baseBranch = safeReviewBranch(task.handoff?.baseBranch) ?? "main";
  const branch = headBranch
    ? `${headBranch} -> ${baseBranch}`
    : undefined;

  return {
    summary,
    files: files.filter(isReviewSafePath),
    nextReviewAction,
    branch,
    curatedSummaryPath: safeSummaryPath(task.handoff?.curatedSummaryPath),
    validationEvidence: (task.handoff?.validationEvidence ?? []).map((item) => ({
      ...item,
      label: redactUnsafeText(item.label) ?? "",
      detail: redactUnsafeText(item.detail) ?? "",
    })),
    proofNeeded: (task.reviewExpectations ?? []).map((item) => redactUnsafeText(item) ?? ""),
  };
}

export function runDisplayForTask(task: Pick<ServiceTask, "run">): {
  step?: string;
  message?: string;
} {
  return {
    step: task.run ? displayProgressStep(task.run) : undefined,
    message: redactUnsafeText(task.run?.displayMessage ?? task.run?.message),
  };
}

function displayProgressStep(run: CodingAssistantRun): string | undefined {
  if (run.displayStep) return run.displayStep;

  switch (run.currentStep) {
    case "Preparing repository":
      return "Preparing workspace";
    case "Preparing Codex App Server thread":
    case "Running Coding Assistant":
      return "Starting Codex";
    case "Detecting changed files":
    case "Creating branch":
    case "Creating review branch":
      return "Checking changes";
    default:
      return run.currentStep;
  }
}

export function safeReviewBranch(branch?: string): string | undefined {
  if (!branch || !isReviewSafePath(branch)) return undefined;
  return branch;
}

export function safeSummaryPath(path?: string): string | undefined {
  return path && isReviewSafePath(path) ? path : undefined;
}

function isReviewSafePath(path: string): boolean {
  return !path.startsWith("/") && !/^[A-Za-z]:[\\/]/.test(path);
}

function redactUnsafeText(value?: string): string | undefined {
  return value
    ?.replace(/(^|[\s(])\/(?:Users|private|tmp|var|Volumes|home|opt|usr)\/[^\s)]+/g, "$1[local path hidden]")
    .replace(/\b[A-Z][A-Z0-9_]*(TOKEN|SECRET|KEY|PASSWORD)=\S+/g, "[environment value hidden]");
}
