export type RepositoryRole = "owner" | "maintainer" | "reviewer" | "operator" | "viewer";

export type ActorSource = "local" | "session" | "mock";

export interface Actor {
  id: string;
  name: string;
  role: RepositoryRole;
  source: ActorSource | string;
}

export type PermissionKey =
  | "repository.view"
  | "repository.configure"
  | "workspace.initialize"
  | "workflow.update"
  | "automation.enable"
  | "automation.disable"
  | "harness.pause"
  | "harness.resume"
  | "harness.tick"
  | "harness.reconcile"
  | "task.create"
  | "task.update"
  | "task.cancel"
  | "task.run_codex"
  | "task.cancel_run"
  | "review.approve"
  | "review.request_changes"
  | "pull_request.open"
  | "pull_request.refresh"
  | "provider.configure"
  | "workspace_provider.experimental_run";

export interface RepositoryAccess {
  role: RepositoryRole;
  permissions: Partial<Record<PermissionKey, boolean>>;
}

export interface AuditEvent {
  id: string;
  at: string;
  actor: {
    id: string;
    name: string;
    role?: RepositoryRole | string;
  };
  repo: string;
  action: string;
  target?: {
    type: "repository" | "task" | "run" | "review" | "pull_request" | "harness" | "workflow";
    id?: string;
  };
  result: "allowed" | "denied" | "completed" | "failed";
  summary: string;
  metadata?: Partial<Record<string, string | number | boolean | null>>;
}

const ROLE_LABELS: Record<RepositoryRole, string> = {
  owner: "Owner",
  maintainer: "Maintainer",
  reviewer: "Reviewer",
  operator: "Operator",
  viewer: "Viewer",
};

const ROLE_PERMISSIONS: Record<RepositoryRole, PermissionKey[]> = {
  owner: [
    "repository.view",
    "repository.configure",
    "workspace.initialize",
    "workflow.update",
    "automation.enable",
    "automation.disable",
    "harness.pause",
    "harness.resume",
    "harness.tick",
    "harness.reconcile",
    "task.create",
    "task.update",
    "task.cancel",
    "task.run_codex",
    "task.cancel_run",
    "review.approve",
    "review.request_changes",
    "pull_request.open",
    "pull_request.refresh",
    "provider.configure",
    "workspace_provider.experimental_run",
  ],
  maintainer: [
    "repository.view",
    "repository.configure",
    "workspace.initialize",
    "workflow.update",
    "automation.enable",
    "automation.disable",
    "harness.pause",
    "harness.resume",
    "harness.tick",
    "harness.reconcile",
    "task.create",
    "task.update",
    "task.cancel",
    "task.run_codex",
    "task.cancel_run",
    "review.approve",
    "review.request_changes",
    "pull_request.open",
    "pull_request.refresh",
    "provider.configure",
  ],
  reviewer: [
    "repository.view",
    "review.approve",
    "review.request_changes",
    "pull_request.refresh",
  ],
  operator: [
    "repository.view",
    "harness.pause",
    "harness.resume",
    "harness.tick",
    "harness.reconcile",
    "task.run_codex",
    "task.cancel_run",
    "pull_request.refresh",
  ],
  viewer: ["repository.view"],
};

export function roleLabel(role?: RepositoryRole | string): string {
  return role && role in ROLE_LABELS ? ROLE_LABELS[role as RepositoryRole] : "Viewer";
}

export function canAccess(
  access: RepositoryAccess | RepositoryRole | null | undefined,
  permission: PermissionKey,
): boolean {
  if (!access) return false;
  if (typeof access === "string") return ROLE_PERMISSIONS[access]?.includes(permission) ?? false;
  return access.permissions[permission] ?? false;
}

export function permissionSummary(access: RepositoryAccess | null | undefined): string {
  const role = access?.role ?? "viewer";
  switch (role) {
    case "owner":
      return "Full repository control.";
    case "maintainer":
      return "Can configure automation, create tasks, run Codex, approve, and open PRs.";
    case "reviewer":
      return "Can approve handoffs, request changes, and refresh PR status.";
    case "operator":
      return "Can manage runs and Harness controls.";
    case "viewer":
      return "Read-only access to tasks, readiness, handoffs, runs, and activity.";
  }
}

export function disabledReason(
  access: RepositoryAccess | null | undefined,
  permission: PermissionKey,
): string | undefined {
  if (canAccess(access, permission)) return undefined;

  const role = access?.role ?? "viewer";
  if (role === "viewer") return "You have read-only access.";
  if (role === "reviewer" && permission === "pull_request.open") {
    return "Reviewers can approve or request changes, but only maintainers and owners can open pull requests.";
  }
  if (role === "operator" && permission === "review.approve") {
    return "Operators can manage runs and Harness controls, but cannot approve handoffs.";
  }
  if (permission === "task.run_codex") {
    return "Only operators, maintainers, and owners can start Coding Assistant runs.";
  }
  if (permission === "harness.pause" || permission === "harness.resume") {
    return "Only operators, maintainers, and owners can pause or resume automation.";
  }
  if (permission === "review.approve") {
    return "Only reviewers, maintainers, and owners can approve handoffs.";
  }
  if (permission === "pull_request.open") {
    return "Only maintainers and owners can open pull requests.";
  }

  return "You do not have permission for this action.";
}

export function auditResultLabel(result: AuditEvent["result"]): string {
  if (result === "denied") return "Denied";
  if (result === "failed") return "Failed";
  if (result === "allowed") return "Allowed";
  return "Completed";
}

export function formatAuditTime(value?: string): string {
  if (!value) return "Time not recorded";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString([], {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}
