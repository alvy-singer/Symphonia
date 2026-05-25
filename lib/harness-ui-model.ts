import type {
  CodingAssistantRun,
  CodingAssistantRunEvent,
  ServiceTask,
  TaskEligibilityExplanation,
} from "@/lib/task-model";
import type { RepositoryAutomationState } from "@/lib/repository-model";

export interface HarnessStatusBadge {
  label: string;
  reason?: string;
  tone: "ready" | "warning" | "neutral";
}

export interface ReviewHandoffView {
  summary?: string;
  files: string[];
  nextReviewAction?: string;
  branch?: string;
  curatedSummaryPath?: string;
}

export function automationLabel(automation?: RepositoryAutomationState | null): string {
  return automation?.enabled ? "Automation on" : "Automation off";
}

export function harnessLabel(automation?: RepositoryAutomationState | null): string {
  return automation?.enabled ? "Automation on" : "Automation off";
}

export function daemonLabel(daemon?: { running?: boolean } | null): string {
  return daemon?.running ? "Background service: Active" : "Background service: Stopped";
}

export function isActiveRun(run?: CodingAssistantRun | null): boolean {
  return run?.state === "queued" || run?.state === "running";
}

export function activeRunPollingTarget(task?: Pick<ServiceTask, "run"> | null): string | null {
  return isActiveRun(task?.run) && task?.run?.id ? task.run.id : null;
}

export function harnessStatusForTask(
  task: ServiceTask,
  eligibility?: TaskEligibilityExplanation,
): HarnessStatusBadge | null {
  if (task.run?.state === "queued") {
    return { label: "Queued", reason: task.run.currentStep, tone: "neutral" };
  }

  if (task.run?.state === "running") {
    return { label: "Running", reason: task.run.currentStep, tone: "neutral" };
  }

  if (task.status === "in_review") {
    return {
      label: "In review",
      reason: task.handoff?.headBranch ?? task.run?.reviewBranch,
      tone: "ready",
    };
  }

  if (task.status === "paused") {
    return {
      label: task.pausedReason === "run_failed" ? "Blocked" : "Paused",
      reason: task.pausedExplanation,
      tone: "warning",
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
  return runEvents.length > 0 ? runEvents : (task.run?.timeline ?? []);
}

export function reviewHandoffForTask(task: ServiceTask): ReviewHandoffView {
  const summary = task.handoff?.summary ?? task.reviewSummary;
  const files =
    task.handoff && task.handoff.filesChanged.length > 0
      ? task.handoff.filesChanged
      : task.filesChanged;
  const nextReviewAction = task.handoff?.nextReviewAction ?? task.nextReviewAction;
  const branch = task.handoff?.headBranch
    ? `${task.handoff.headBranch} -> ${task.handoff.baseBranch ?? "main"}`
    : undefined;

  return {
    summary,
    files,
    nextReviewAction,
    branch,
    curatedSummaryPath: task.handoff?.curatedSummaryPath,
  };
}
