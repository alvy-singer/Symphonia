import type {
  RepositoryReadiness,
  RepositoryReadinessAction,
  RepositoryReadinessCategory,
  RepositoryReadinessCheck,
} from "@/lib/repository-model";

export type ReadinessTone = "ready" | "warning" | "blocked" | "neutral";

const ACTION_PRIORITY: Record<string, number> = {
  create_workflow: 10,
  initialize_workspace: 20,
  initialize_spec_workspace: 30,
  connect_github: 40,
  setup_codex: 50,
  enable_automation: 60,
  resume_harness: 70,
  configure_validation: 80,
};

export function readinessSummary(readiness: RepositoryReadiness): string {
  const passed = readiness.checks.filter((check) => check.status === "passed").length;
  const warnings = readiness.checks.filter((check) => check.status === "warning").length;
  const blocked = readiness.checks.filter((check) => check.status === "failed").length;

  if (blocked === 0 && warnings === 0) return `${passed} ready`;
  return `${passed} ready · ${warnings} warnings · ${blocked} blocked`;
}

export function readinessPrimaryAction(
  readiness: RepositoryReadiness,
): RepositoryReadinessAction | null {
  const explicit = readiness.nextActions?.[0];
  if (explicit) return explicit;

  return readiness.checks
    .filter((check) => check.status === "failed" || check.status === "warning")
    .map((check) => check.action)
    .filter((action): action is RepositoryReadinessAction => Boolean(action))
    .sort((a, b) => actionPriority(a) - actionPriority(b))[0] ?? null;
}

export function readinessTone(state: RepositoryReadiness["state"]): ReadinessTone {
  if (state === "ready") return "ready";
  if (state === "warning") return "warning";
  if (state === "blocked" || state === "needs_setup") return "blocked";
  return "neutral";
}

export function groupReadinessChecks(
  checks: RepositoryReadinessCheck[],
): Record<RepositoryReadinessCategory, RepositoryReadinessCheck[]> {
  const groups: Record<RepositoryReadinessCategory, RepositoryReadinessCheck[]> = {
    workspace: [],
    planning: [],
    automation: [],
    provider: [],
    validation: [],
    github: [],
    review: [],
  };

  for (const check of checks) {
    groups[check.category]?.push(check);
  }

  return groups;
}

export function readinessBlocksAutomation(readiness: RepositoryReadiness): boolean {
  return readiness.checks.some(
    (check) =>
      check.status === "failed" &&
      (check.category === "workspace" ||
        check.category === "provider" ||
        check.category === "github" ||
        check.id === "harness_online"),
  );
}

function actionPriority(action: RepositoryReadinessAction): number {
  return ACTION_PRIORITY[action.id] ?? 100;
}
