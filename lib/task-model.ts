import type { Priority, User } from "@/data/mock";

export type TaskStatus =
  | "todo"
  | "in_progress"
  | "in_review"
  | "paused"
  | "completed"
  | "canceled";

export type PausedReason =
  | "run_failed"
  | "waiting_for_user"
  | "blocked_by_setup"
  | "waiting_for_sync"
  | "needs_clarification";

export type TaskLifecycleEvent =
  | "start"
  | "submit_review"
  | "fail_run"
  | "pause_run"
  | "approve"
  | "request_changes"
  | "open_pr"
  | "merge_pr"
  | "cancel";

export interface GitHubTaskMetadata {
  repo?: {
    owner?: string;
    name?: string;
    url?: string;
    default_branch?: string;
  };
  issue?: {
    owner?: string;
    repo?: string;
    number?: number;
    url?: string;
    state?: string;
  };
  pull_request?: {
    owner?: string;
    repo?: string;
    number?: number;
    url?: string;
    state?: "open" | "closed" | "merged" | string;
    merged?: boolean;
    head_branch?: string;
    base_branch?: string;
  };
}

export interface CodingAssistantRun {
  id: string;
  state: "queued" | "running" | "completed" | "failed" | "canceled" | string;
  provider?: string;
  label?: string;
  currentStep?: string;
  message?: string;
  displayStep?: string;
  displayMessage?: string;
  workspacePath?: string;
  codexThreadId?: string;
  turnId?: string;
  eligibilityReason?: string;
  reviewBranch?: string;
  curatedSummaryPath?: string;
  timeline?: CodingAssistantRunEvent[];
  startedAt?: string;
  completedAt?: string;
}

export interface CodingAssistantRunEvent {
  id?: string;
  event?: "run-progress" | string;
  at?: string;
  label?: string;
  runId?: string;
  taskKey?: string;
  state?: string;
  displayStep?: string;
  displayMessage?: string;
  reviewBranch?: string;
  curatedSummaryPath?: string;
  updatedAt?: string;
}

export interface CodingAssistantHandoff {
  summary?: string;
  filesChanged: string[];
  nextReviewAction?: string;
  headBranch?: string;
  baseBranch?: string;
  curatedSummaryPath?: string;
  validationEvidence?: ValidationEvidence[];
}

export interface ValidationEvidence {
  label: string;
  status: "passed" | "failed" | "not_run";
  detail: string;
}

export interface TaskEligibilityCheck {
  ok: boolean;
  code: string;
  message: string;
}

export interface TaskEligibilityExplanation {
  eligible: boolean;
  code: string;
  reason: string;
  checks: TaskEligibilityCheck[];
}

export interface ReviewNote {
  id: string;
  created_at?: string;
  original_feedback: string;
  requested_changes: string[];
}

export interface ServiceTask {
  key: string;
  title: string;
  status: TaskStatus;
  priority: Priority;
  project?: string;
  assistant?: string;
  pausedReason?: PausedReason;
  pausedExplanation?: string;
  run?: CodingAssistantRun | null;
  handoff?: CodingAssistantHandoff | null;
  github?: GitHubTaskMetadata | null;
  githubIssue?: string;
  githubIssueState?: string;
  githubPr?: string;
  githubPrState?: "open" | "merged" | string;
  githubSyncEnabled?: boolean;
  reviewApproved?: boolean;
  reviewState?: "approved" | "changes_requested" | string;
  reviewSummary?: string;
  filesChanged: string[];
  sourceMilestone?: string;
  sourcePlan?: string;
  sourceRequirements?: string;
  sourceDiscussion?: string;
  sourceDecisions?: string[];
  generatedBy?: string;
  generationId?: string;
  proposalItemId?: string;
  dependsOn?: string[];
  reviewExpectations?: string[];
  nextStep?: "open_pull_request" | "refresh_pr_status" | string;
  nextReviewAction?: string;
  updatedAt?: string;
  repo: string;
  path: string;
  body: string;
  assignee?: User;
  labels: { id: string; name: string; color: string }[];
}

export const TASK_STATUS_ORDER: TaskStatus[] = [
  "todo",
  "in_progress",
  "in_review",
  "paused",
  "completed",
  "canceled",
];

export const TASK_STATUS_LABELS: Record<TaskStatus, string> = {
  todo: "To-do",
  in_progress: "In Progress",
  in_review: "In Review",
  paused: "Paused",
  completed: "Completed",
  canceled: "Canceled",
};

export const PAUSED_REASON_LABELS: Record<PausedReason, string> = {
  run_failed: "Run failed",
  waiting_for_user: "Waiting for user",
  blocked_by_setup: "Blocked by setup",
  waiting_for_sync: "Waiting for sync",
  needs_clarification: "Needs clarification",
};

export function statusLabel(status: TaskStatus): string {
  return TASK_STATUS_LABELS[status] ?? status;
}

export function pausedReasonLabel(reason?: PausedReason): string | undefined {
  return reason ? PAUSED_REASON_LABELS[reason] : undefined;
}
