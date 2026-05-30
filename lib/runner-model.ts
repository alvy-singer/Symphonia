export type RunnerMode = "local_service" | "remote_runner";
export type RunnerStatus = "online" | "offline" | "stale" | "disabled";

export interface RunnerCapabilities {
  codexAppServer: boolean;
  localGitWorktree: boolean;
  experimentalSandbox: boolean;
  validation: boolean;
}

export interface RunnerLimits {
  maxConcurrentRuns: number;
}

export interface RunnerStatusRow {
  id: string;
  name: string;
  mode: RunnerMode;
  status: RunnerStatus;
  lastHeartbeatAt?: string;
  capabilities: RunnerCapabilities;
  limits: RunnerLimits;
  currentRuns: number;
}

export type RunnerTone = "ready" | "warning" | "blocked" | "neutral";

export function runnerStatusLabel(runner: RunnerStatusRow): string {
  if (runner.status === "online") {
    return runner.mode === "remote_runner" ? "Online · Experimental" : "Online";
  }
  if (runner.status === "stale") return "Stale";
  if (runner.status === "offline") return "Offline";
  if (runner.status === "disabled") return "Disabled";
  return "Unknown";
}

export function runnerStatusTone(runner: RunnerStatusRow): RunnerTone {
  if (runner.status === "disabled") return "neutral";
  if (runner.status === "offline") return "blocked";
  if (runner.status === "stale") return "warning";
  if (runner.mode === "remote_runner") return "warning";
  if (runner.capabilities.codexAppServer) return "ready";
  return "warning";
}

export function runnerCapabilitySummary(runner: RunnerStatusRow): string {
  const capabilities = [
    runner.capabilities.codexAppServer ? "Codex ready" : null,
    runner.capabilities.localGitWorktree ? "Local Git worktree" : null,
    runner.capabilities.experimentalSandbox ? "Experimental sandbox" : null,
    runner.capabilities.validation ? "Validation ready" : null,
  ].filter((value): value is string => Boolean(value));

  return capabilities.length > 0 ? capabilities.join(" · ") : "No runner capabilities";
}

export function runnerCapacityLabel(runner: RunnerStatusRow): string {
  return `${Math.max(0, runner.currentRuns)} / ${Math.max(1, runner.limits.maxConcurrentRuns)}`;
}

export function canSelectRunnerForHarness(runner: RunnerStatusRow): boolean {
  return (
    runner.mode === "local_service" &&
    runner.status === "online" &&
    runner.capabilities.codexAppServer &&
    runner.currentRuns < runner.limits.maxConcurrentRuns
  );
}
