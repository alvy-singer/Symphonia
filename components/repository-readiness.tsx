"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  Circle,
  ExternalLink,
  Loader2,
  RefreshCw,
  ShieldCheck,
  XCircle,
} from "lucide-react";
import type {
  RepositoryReadiness,
  RepositoryReadinessAction,
  RepositoryReadinessCategory,
  RepositoryReadinessCheck,
} from "@/lib/repository-model";
import {
  groupReadinessChecks,
  readinessBlocksAutomation,
  readinessPrimaryAction,
  readinessSummary,
  readinessTone,
  type ReadinessTone,
} from "@/lib/readiness-ui-model";
import {
  canAccess,
  disabledReason,
  type PermissionKey,
  type RepositoryAccess,
} from "@/lib/access-ui-model";
import { cn } from "@/lib/utils";

const CATEGORY_LABELS: Record<RepositoryReadinessCategory, string> = {
  workspace: "Workspace",
  planning: "Planning",
  automation: "Automation",
  provider: "Codex",
  runner: "Runner capacity",
  validation: "Validation",
  github: "GitHub",
  review: "Review branches",
};

export function RepositoryReadinessCompact({
  repoKey,
  access,
}: {
  repoKey: string;
  access?: RepositoryAccess | null;
}) {
  return <RepositoryReadinessSurface repoKey={repoKey} access={access} variant="compact" />;
}

export function RepositoryReadinessDetails({
  repoKey,
  access,
}: {
  repoKey: string;
  access?: RepositoryAccess | null;
}) {
  return <RepositoryReadinessSurface repoKey={repoKey} access={access} variant="detailed" />;
}

export function RepositoryReadinessTaskBanner({
  repoKey,
  access,
}: {
  repoKey: string;
  access?: RepositoryAccess | null;
}) {
  return <RepositoryReadinessSurface repoKey={repoKey} access={access} variant="banner" />;
}

function RepositoryReadinessSurface({
  repoKey,
  access,
  variant,
}: {
  repoKey: string;
  access?: RepositoryAccess | null;
  variant: "compact" | "detailed" | "banner";
}) {
  const [readiness, setReadiness] = useState<RepositoryReadiness | null>(null);
  const [loading, setLoading] = useState(true);
  const [pendingAction, setPendingAction] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(
    async () => {
      setError(null);
      const next = await fetchRepositoryReadiness(repoKey);
      setReadiness(next);
    },
    [repoKey],
  );

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    refresh()
      .catch((err: unknown) => {
        if (!cancelled) setError(safeMessage(err, "Could not load repository readiness"));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    const handler = () => {
      refresh().catch(() => {});
    };
    window.addEventListener("symphonia:readinessUpdated", handler);
    return () => {
      cancelled = true;
      window.removeEventListener("symphonia:readinessUpdated", handler);
    };
  }, [refresh]);

  const runAction = async (action: RepositoryReadinessAction) => {
    if (action.kind === "navigate" || action.kind === "connect") return;

    setPendingAction(action.id);
    setError(null);
    try {
      const next = await postReadinessAction(repoKey, action);
      setReadiness(next ?? (await fetchRepositoryReadiness(repoKey)));
      window.dispatchEvent(new CustomEvent("symphonia:readinessUpdated"));
    } catch (err) {
      setError(safeMessage(err, "Could not update repository setup"));
    } finally {
      setPendingAction(null);
    }
  };

  if (variant === "banner" && readiness && !readinessBlocksAutomation(readiness)) {
    return null;
  }

  if (variant === "banner") {
    return (
      <ReadinessBanner
        repoKey={repoKey}
        readiness={readiness}
        loading={loading}
        error={error}
        pendingAction={pendingAction}
        access={access}
        onAction={runAction}
      />
    );
  }

  return variant === "compact" ? (
    <CompactReadiness
      repoKey={repoKey}
      readiness={readiness}
      loading={loading}
      error={error}
      pendingAction={pendingAction}
      access={access}
      onAction={runAction}
    />
  ) : (
    <DetailedReadiness
      repoKey={repoKey}
      readiness={readiness}
      loading={loading}
      error={error}
      pendingAction={pendingAction}
      access={access}
      onAction={runAction}
    />
  );
}

function CompactReadiness({
  repoKey,
  readiness,
  loading,
  error,
  pendingAction,
  access,
  onAction,
}: ReadinessRenderProps) {
  const action = readiness ? readinessPrimaryAction(readiness) : null;
  const tone = readiness ? readinessTone(readiness.state) : "neutral";

  return (
    <section className="rounded-[10px] border bg-card p-3 shadow-[var(--elevation-card)]">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <span className={cn("grid h-8 w-8 place-items-center rounded-[8px]", toneClass(tone))}>
              <ShieldCheck className="h-4 w-4" />
            </span>
            <div>
              <h2 className="text-sm font-medium">Repository readiness</h2>
              <p className="text-xs text-muted-foreground">
                {loading ? "Checking setup" : readiness ? readinessSummary(readiness) : "Unavailable"}
              </p>
            </div>
          </div>
          {error && <p className="mt-2 text-xs text-amber-700 dark:text-amber-300">{error}</p>}
        </div>
        {loading ? <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" /> : null}
      </div>

      {readiness && (
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <ReadinessStatePill tone={tone} label={stateLabel(readiness.state)} />
          {action && (
            <ActionControl
              repoKey={repoKey}
              action={action}
              pending={pendingAction === action.id}
              access={access}
              onAction={onAction}
            />
          )}
        </div>
      )}
    </section>
  );
}

function DetailedReadiness({
  repoKey,
  readiness,
  loading,
  error,
  pendingAction,
  access,
  onAction,
}: ReadinessRenderProps) {
  const groups = readiness ? groupReadinessChecks(readiness.checks) : null;
  const action = readiness ? readinessPrimaryAction(readiness) : null;
  const tone = readiness ? readinessTone(readiness.state) : "neutral";

  return (
    <section className="rounded-[10px] border bg-card shadow-[var(--elevation-card)]">
      <div className="flex items-start justify-between gap-3 p-3">
        <div className="flex min-w-0 items-start gap-3">
          <span className={cn("grid h-8 w-8 place-items-center rounded-[8px]", toneClass(tone))}>
            <ShieldCheck className="h-4 w-4" />
          </span>
          <div className="min-w-0">
            <div className="text-sm font-medium">Repository readiness</div>
            <div className="text-xs text-muted-foreground">
              {loading ? "Checking setup" : readiness ? readinessSummary(readiness) : "Unavailable"}
            </div>
            {error && <div className="mt-2 text-xs text-amber-700 dark:text-amber-300">{error}</div>}
          </div>
        </div>
        <div className="flex shrink-0 flex-wrap justify-end gap-1.5">
          {readiness && <ReadinessStatePill tone={tone} label={stateLabel(readiness.state)} />}
          {action && (
            <ActionControl
              repoKey={repoKey}
              action={action}
              pending={pendingAction === action.id}
              access={access}
              onAction={onAction}
            />
          )}
        </div>
      </div>

      {loading && (
        <div className="border-t px-3 py-4 text-xs text-muted-foreground">Loading readiness checks</div>
      )}

      {groups && (
        <div className="divide-y border-t">
          {(Object.keys(CATEGORY_LABELS) as RepositoryReadinessCategory[]).map((category) => (
            <ReadinessGroup
              key={category}
              repoKey={repoKey}
              label={CATEGORY_LABELS[category]}
              checks={groups[category]}
              pendingAction={pendingAction}
              access={access}
              onAction={onAction}
            />
          ))}
        </div>
      )}

      {readiness?.scan && (
        <div className="border-t px-3 py-3">
          <div className="mb-2 text-[11px] font-medium uppercase text-muted-foreground">
            Scanner advisory
          </div>
          <div className="grid gap-2 text-xs sm:grid-cols-3">
            <ScanMetric label="Detected" value={readiness.scan.detected.join(", ") || "None"} />
            <ScanMetric label="Files" value={readiness.scan.files.join(", ") || "None"} />
            <ScanMetric
              label="Validation"
              value={
                readiness.scan.suggestedValidation.map((item) => item.command).join(", ") ||
                "No suggestion"
              }
            />
          </div>
        </div>
      )}
    </section>
  );
}

function ReadinessBanner({
  repoKey,
  readiness,
  loading,
  error,
  pendingAction,
  access,
  onAction,
}: ReadinessRenderProps) {
  const action = readiness ? readinessPrimaryAction(readiness) : null;

  return (
    <div className="border-b bg-amber-500/10 px-5 py-2 text-xs text-amber-800 dark:text-amber-200">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex min-w-0 items-center gap-2">
          <AlertTriangle className="h-4 w-4 shrink-0" />
          <span className="min-w-0">
            {error
              ? error
              : loading
                ? "Checking automation setup"
                : readiness?.summary ?? "Automation setup incomplete."}
          </span>
        </div>
        {action && (
          <ActionControl
            repoKey={repoKey}
            action={action}
            pending={pendingAction === action.id}
            access={access}
            onAction={onAction}
          />
        )}
      </div>
    </div>
  );
}

function ReadinessGroup({
  repoKey,
  label,
  checks,
  pendingAction,
  access,
  onAction,
}: {
  repoKey: string;
  label: string;
  checks: RepositoryReadinessCheck[];
  pendingAction: string | null;
  access?: RepositoryAccess | null;
  onAction: (action: RepositoryReadinessAction) => void;
}) {
  if (checks.length === 0) return null;

  return (
    <div className="px-3 py-3">
      <div className="mb-2 text-[11px] font-medium uppercase text-muted-foreground">{label}</div>
      <ul className="space-y-2">
        {checks.map((check) => (
          <li key={check.id} className="flex items-start justify-between gap-3 text-xs">
            <div className="flex min-w-0 items-start gap-2">
              <ReadinessCheckIcon status={check.status} />
              <div className="min-w-0">
                <div className="font-medium">{check.label}</div>
                <div className="mt-0.5 text-muted-foreground">{check.detail}</div>
              </div>
            </div>
            {check.action && (
              <ActionControl
                repoKey={repoKey}
                action={check.action}
                pending={pendingAction === check.action.id}
                access={access}
                onAction={onAction}
              />
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}

function ActionControl({
  repoKey,
  action,
  pending,
  access,
  onAction,
}: {
  repoKey: string;
  action: RepositoryReadinessAction;
  pending: boolean;
  access?: RepositoryAccess | null;
  onAction: (action: RepositoryReadinessAction) => void;
}) {
  if (action.kind === "navigate" || action.kind === "connect") {
    return (
      <Link
        href={resolveNavigationHref(repoKey, action)}
        className="inline-flex shrink-0 items-center gap-1.5 rounded-[8px] border bg-background px-2.5 py-1 text-xs text-foreground transition-colors hover:bg-accent"
      >
        {action.label}
        <ExternalLink className="h-3 w-3" />
      </Link>
    );
  }

  const permission = permissionForReadinessAction(action);
  const blockedReason =
    access && permission && !canAccess(access, permission)
      ? setupDisabledReason(access, permission, action)
      : undefined;

  return (
    <button
      type="button"
      onClick={() => onAction(action)}
      disabled={pending || Boolean(blockedReason)}
      title={blockedReason}
      className="inline-flex shrink-0 items-center gap-1.5 rounded-[8px] border bg-background px-2.5 py-1 text-xs text-foreground transition-colors hover:bg-accent disabled:cursor-not-allowed disabled:opacity-60"
    >
      {pending ? <Loader2 className="h-3 w-3 animate-spin" /> : <RefreshCw className="h-3 w-3" />}
      {pending ? "Working..." : action.label}
    </button>
  );
}

function ReadinessStatePill({ tone, label }: { tone: ReadinessTone; label: string }) {
  return (
    <span
      className={cn(
        "inline-flex shrink-0 items-center rounded-[8px] border px-2.5 py-1 text-xs",
        tone === "ready" &&
          "border-emerald-500/30 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400",
        tone === "warning" &&
          "border-amber-500/30 bg-amber-500/10 text-amber-700 dark:text-amber-300",
        tone === "blocked" &&
          "border-red-500/30 bg-red-500/10 text-red-700 dark:text-red-300",
        tone === "neutral" && "text-muted-foreground",
      )}
    >
      {label}
    </span>
  );
}

function ReadinessCheckIcon({ status }: { status: RepositoryReadinessCheck["status"] }) {
  if (status === "passed") return <CheckCircle2 className="mt-0.5 h-3.5 w-3.5 shrink-0 text-emerald-500" />;
  if (status === "warning") return <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-500" />;
  if (status === "failed") return <XCircle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-red-500" />;
  return <Circle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" />;
}

function ScanMetric({ label, value }: { label: string; value: string }) {
  return (
    <div className="min-w-0 border-l px-2.5 py-1">
      <div className="text-[11px] text-muted-foreground">{label}</div>
      <div className="truncate text-sm font-medium">{value}</div>
    </div>
  );
}

async function fetchRepositoryReadiness(repoKey: string): Promise<RepositoryReadiness> {
  const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/readiness`, {
    cache: "no-store",
  });
  const payload = (await res.json()) as { readiness?: RepositoryReadiness; error?: string };
  if (!res.ok || !payload.readiness) {
    throw new Error(payload.error ?? "Could not load repository readiness");
  }
  return payload.readiness;
}

async function postReadinessAction(
  repoKey: string,
  action: RepositoryReadinessAction,
): Promise<RepositoryReadiness | null> {
  const href = resolveActionHref(repoKey, action);
  const res = await fetch(href, {
    method: "POST",
    cache: "no-store",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(action.id === "create_workflow" ? { template: "simple-pr" } : {}),
  });
  const payload = (await res.json().catch(() => ({}))) as {
    readiness?: RepositoryReadiness;
    error?: string;
  };
  if (!res.ok) throw new Error(payload.error ?? "Could not update repository setup");
  return payload.readiness ?? null;
}

function resolveActionHref(repoKey: string, action: RepositoryReadinessAction): string {
  if (!action.href) return `/api/repositories/${encodeURIComponent(repoKey)}/readiness`;
  if (action.href.startsWith("/api/")) return action.href;
  return `/api/repositories/${encodeURIComponent(repoKey)}${action.href}`;
}

function resolveNavigationHref(repoKey: string, action: RepositoryReadinessAction): string {
  const slug = repoKey.toLowerCase();
  if (!action.href) return `/r/${slug}`;
  if (action.href.startsWith("/api/")) return action.href;
  return `/r/${slug}${action.href}`;
}

function stateLabel(state: RepositoryReadiness["state"]): string {
  if (state === "ready") return "Ready";
  if (state === "warning") return "Warnings";
  if (state === "needs_setup") return "Needs setup";
  return "Blocked";
}

function toneClass(tone: ReadinessTone): string {
  if (tone === "ready") return "bg-emerald-500/10 text-emerald-600 dark:text-emerald-400";
  if (tone === "warning") return "bg-amber-500/10 text-amber-700 dark:text-amber-300";
  if (tone === "blocked") return "bg-red-500/10 text-red-700 dark:text-red-300";
  return "bg-muted text-foreground";
}

function safeMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

type ReadinessRenderProps = {
  repoKey: string;
  readiness: RepositoryReadiness | null;
  loading: boolean;
  error: string | null;
  pendingAction: string | null;
  access?: RepositoryAccess | null;
  onAction: (action: RepositoryReadinessAction) => void;
};

function permissionForReadinessAction(
  action: RepositoryReadinessAction,
): PermissionKey | undefined {
  switch (action.id) {
    case "create_workflow":
      return "workflow.update";
    case "initialize_workspace":
    case "initialize_spec_workspace":
      return "workspace.initialize";
    case "enable_automation":
      return "automation.enable";
    case "resume_harness":
      return "harness.resume";
    default:
      return undefined;
  }
}

function setupDisabledReason(
  access: RepositoryAccess,
  permission: PermissionKey,
  action: RepositoryReadinessAction,
): string {
  if (permission === "workspace.initialize" || permission === "workflow.update") {
    return `Ask an owner or maintainer to ${action.label.toLowerCase()}.`;
  }

  return disabledReason(access, permission) ?? "You do not have permission for this action.";
}
