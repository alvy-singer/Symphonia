"use client";

import { useEffect, useMemo, useState } from "react";
import { cn } from "@/lib/utils";
import {
  externalIssues,
  type ExternalIssue,
  type ImportSource,
} from "@/data/mock";
import type {
  CodingAssistantProviderCatalog,
  CodingAssistantProviderStatus,
  GitHubConnectionState,
  RepositoryAutomationState,
} from "@/lib/repository-model";
import {
  RepositoryReadinessCompact,
  RepositoryReadinessDetails,
} from "@/components/repository-readiness";
import {
  groupHarnessDecisions,
  harnessStatusLabel,
  type HarnessDecision,
} from "@/lib/harness-ui-model";
import {
  auditResultLabel,
  canAccess,
  disabledReason,
  formatAuditTime,
  permissionSummary,
  roleLabel,
  type AuditEvent,
  type RepositoryAccess,
} from "@/lib/access-ui-model";
import {
  canHarnessRunProvider,
  providerMissingCapabilityLabels,
  providerStatusLabel,
  providerStatusTone,
  providerSupportedCapabilityLabels,
} from "@/lib/provider-ui-model";
import {
  runnerCapabilitySummary,
  runnerCapacityLabel,
  runnerStatusLabel,
  runnerStatusTone,
  runnerTrustDetail,
  type RunnerStatusRow,
} from "@/lib/runner-model";
import {
  sandboxSmokeLabel,
  sandboxSmokeTone,
} from "@/lib/sandbox-ui-model";
import {
  User as UserIcon,
  Bell,
  Bot,
  Palette,
  KeyRound,
  Building2,
  Plug,
  CreditCard,
  Check,
  Activity,
  AlertTriangle,
  Github,
  ExternalLink,
  Link2,
  ChevronRight,
  ChevronDown,
  Pause,
  Play,
  RefreshCw,
  ShieldCheck,
} from "lucide-react";

type SectionId =
  | "profile"
  | "appearance"
  | "notifications"
  | "workspace"
  | "automation"
  | "integrations"
  | "security"
  | "billing";

const sections: { id: SectionId; label: string; icon: typeof UserIcon }[] = [
  { id: "profile", label: "Profile", icon: UserIcon },
  { id: "appearance", label: "Appearance", icon: Palette },
  { id: "notifications", label: "Notifications", icon: Bell },
  { id: "workspace", label: "Repository", icon: Building2 },
  { id: "automation", label: "Automation", icon: Bot },
  { id: "integrations", label: "Integrations", icon: Plug },
  { id: "security", label: "Security", icon: KeyRound },
  { id: "billing", label: "Billing", icon: CreditCard },
];

export function SettingsView({ repoKey }: { repoKey: string }) {
  const [active, setActive] = useState<SectionId>("automation");
  const [access, setAccess] = useState<RepositoryAccess | null>(null);
  const [auditEvents, setAuditEvents] = useState<AuditEvent[]>([]);
  const [name, setName] = useState("Ava Martinez");
  const [email, setEmail] = useState("ava@symphonia.app");
  const [bio, setBio] = useState("Design lead, building calmer software.");
  const [workspaceName, setWorkspaceName] = useState("Symphonia");
  const [notif, setNotif] = useState({
    mentions: true,
    assigned: true,
    weekly: false,
    marketing: false,
  });

  useEffect(() => {
    let cancelled = false;
    Promise.all([fetchRepositoryAccess(repoKey), fetchRepositoryAudit(repoKey)])
      .then(([nextAccess, nextEvents]) => {
        if (cancelled) return;
        setAccess(nextAccess);
        setAuditEvents(nextEvents);
      })
      .catch(() => {
        if (!cancelled) {
          setAccess(null);
          setAuditEvents([]);
        }
      });

    return () => {
      cancelled = true;
    };
  }, [repoKey]);

  return (
    <div className="flex h-full flex-col">
      <header className="flex items-center justify-between border-b px-5 py-3">
        <span className="text-[15px] font-bold tracking-[-0.02em]">Settings</span>
        <span className="text-[11px] text-muted-foreground font-mono">{repoKey}</span>
      </header>

      <div className="flex flex-1 min-h-0">
        <nav className="hidden md:flex w-56 shrink-0 flex-col border-r p-2 gap-0.5">
          {sections.map((s) => {
            const Icon = s.icon;
            const isActive = active === s.id;
            return (
              <button
                key={s.id}
                onClick={() => setActive(s.id)}
                className={cn(
                  "flex items-center gap-2 rounded-[8px] px-2 py-1.5 text-left text-sm transition-colors",
                  isActive
                    ? "bg-accent text-foreground font-medium"
                    : "text-muted-foreground hover:bg-accent/60 hover:text-foreground",
                )}
              >
                <Icon className="h-4 w-4" />
                {s.label}
              </button>
            );
          })}
        </nav>

        <div className="relative md:hidden">
          <div className="flex gap-1 overflow-x-auto border-b px-3 py-2">
            {sections.map((s) => (
              <button
                key={s.id}
                onClick={() => setActive(s.id)}
                className={cn(
                  "rounded-[8px] px-2.5 py-1 text-xs whitespace-nowrap",
                  active === s.id
                    ? "bg-accent text-foreground font-medium"
                    : "text-muted-foreground hover:bg-accent/60",
                )}
              >
                {s.label}
              </button>
            ))}
          </div>
          <div
            className="pointer-events-none absolute right-0 top-0 h-full w-6 bg-gradient-to-l from-background to-transparent"
            aria-hidden="true"
          />
        </div>

        <main className="flex-1 overflow-y-auto p-6 max-w-3xl">
          {active === "profile" && (
            <Section title="Profile" description="Your name and contact details across Symphonia.">
              <div className="flex items-center gap-4">
                <span className="grid h-16 w-16 place-items-center rounded-full bg-rose-500 text-sm font-medium text-white">
                  AM
                </span>
                <div className="space-y-1">
                  <button
                    disabled
                    title="Coming soon"
                    className="cursor-not-allowed rounded-[8px] border px-3 py-1 text-xs opacity-60"
                  >
                    Upload photo
                  </button>
                  <p className="text-xs text-muted-foreground">PNG or JPG, up to 2 MB.</p>
                </div>
              </div>
              <Field label="Full name">
                <input
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  required
                  maxLength={100}
                  className="w-full rounded-[8px] border bg-background px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
                />
              </Field>
              <Field label="Email">
                <input
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  type="email"
                  required
                  maxLength={200}
                  className="w-full rounded-[8px] border bg-background px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
                />
              </Field>
              <Field label="Short bio">
                <textarea
                  value={bio}
                  onChange={(e) => setBio(e.target.value)}
                  rows={3}
                  maxLength={300}
                  className="w-full resize-none rounded-[8px] border bg-background px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
                />
              </Field>
              <SaveBar />
              <RepositoryReadinessCompact repoKey={repoKey} />
            </Section>
          )}

          {active === "appearance" && (
            <Section title="Appearance" description="Tune the density of the dark editorial interface.">
              <ToggleRow
                label="Compact density"
                description="Tighter row heights across lists."
                checked={false}
                onChange={() => {}}
                disabled
                disabledReason="Coming soon"
              />
            </Section>
          )}

          {active === "notifications" && (
            <Section title="Notifications" description="Choose what shows up in your inbox and email.">
              <ToggleRow
                label="Mentions"
                description="Someone mentions you in a comment or thread."
                checked={notif.mentions}
                onChange={(v) => setNotif({ ...notif, mentions: v })}
              />
              <ToggleRow
                label="Assigned to me"
                description="You're assigned to a task or project."
                checked={notif.assigned}
                onChange={(v) => setNotif({ ...notif, assigned: v })}
              />
              <ToggleRow
                label="Weekly digest"
                description="A Monday summary of your repository."
                checked={notif.weekly}
                onChange={(v) => setNotif({ ...notif, weekly: v })}
              />
              <ToggleRow
                label="Product updates"
                description="Occasional emails about what's new in Symphonia."
                checked={notif.marketing}
                onChange={(v) => setNotif({ ...notif, marketing: v })}
              />
            </Section>
          )}

          {active === "workspace" && (
            <Section title="Repository" description="Settings that apply to the whole repository.">
              <Field label="Repository alias">
                <input
                  value={workspaceName}
                  onChange={(e) => setWorkspaceName(e.target.value)}
                  required maxLength={50}
                  className="w-full rounded-[8px] border bg-background px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
                />
              </Field>
              <Field label="Repository URL">
                <div className="flex items-stretch overflow-hidden rounded-[8px] border">
                  <span className="bg-muted px-3 py-1.5 text-xs text-muted-foreground border-r flex items-center">
                    symphonia.app/
                  </span>
                  <input
                    defaultValue={repoKey.toLowerCase()}
                    className="flex-1 bg-background px-3 py-1.5 text-sm focus:outline-none"
                    aria-label="Repository URL slug"
                  />
                </div>
              </Field>
              <Field label="Default task prefix">
                <input
                  defaultValue={repoKey}
                  className="w-32 rounded-[8px] border bg-background px-3 py-1.5 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-ring"
                  aria-label="Default task prefix"
                />
              </Field>
              <SaveBar />
            </Section>
          )}

          {active === "integrations" && (
            <Section
              title="Integrations"
              description="Connect Symphonia to the tools your team already uses."
            >
              <GitHubIntegration repoKey={repoKey} />
              <IntegrationRow
                source="linear"
                name="Linear"
                desc="Import issues and projects, or link tasks to existing Linear items."
                repoKey={repoKey}
              />
              <SimpleIntegration
                name="Slack"
                desc="Post run summaries and review requests to channels and DMs."
                initialConnected
              />
            </Section>
          )}

          {active === "automation" && (
            <Section
              title="Automation"
              description="Control local-first Codex execution for this repository."
            >
              <AccessPanel access={access} />
              <AutomationIntegration repoKey={repoKey} access={access} />
              <RepositoryReadinessDetails repoKey={repoKey} access={access} />
              <HarnessPanel repoKey={repoKey} access={access} />
              <ActivityPanel events={auditEvents} />
            </Section>
          )}

          {active === "security" && (
            <Section title="Security" description="Protect your account and audit recent activity.">
              <Field label="Change password">
                <div className="space-y-2 max-w-sm">
                  <input
                    type="password"
                    placeholder="Current password"
                    disabled
                    title="Coming soon"
                    className="w-full cursor-not-allowed rounded-[8px] border bg-background px-3 py-1.5 text-sm opacity-60 focus:outline-none focus:ring-2 focus:ring-ring"
                  />
                  <input
                    type="password"
                    placeholder="New password"
                    disabled
                    title="Coming soon"
                    className="w-full cursor-not-allowed rounded-[8px] border bg-background px-3 py-1.5 text-sm opacity-60 focus:outline-none focus:ring-2 focus:ring-ring"
                  />
                </div>
              </Field>
              <ToggleRow
                label="Two-factor authentication"
                description="Require a second factor on every sign-in."
                checked={true}
                onChange={() => {}}
                disabled
                disabledReason="Coming soon"
              />
              <SaveBar />
            </Section>
          )}

          {active === "billing" && (
            <Section title="Billing" description="Manage your plan, seats and invoices.">
              <div className="rounded-[10px] border bg-card p-4 shadow-[var(--elevation-card)]">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="text-xs uppercase tracking-wider text-muted-foreground">
                      Current plan
                    </div>
                    <div className="text-[18px] font-bold tracking-[-0.02em]">Business · 12 seats</div>
                    <div className="text-xs text-muted-foreground">
                      Renews May 28, 2026 · $192/mo
                    </div>
                  </div>
                  <button
                    disabled
                    title="Coming soon"
                    className="cursor-not-allowed rounded-[8px] border px-3 py-1.5 text-xs opacity-60"
                  >
                    Manage plan
                  </button>
                </div>
              </div>
            </Section>
          )}
        </main>
      </div>
    </div>
  );
}

async function fetchRepositoryAccess(repoKey: string): Promise<RepositoryAccess> {
  const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/access`, {
    cache: "no-store",
  });
  const payload = (await res.json()) as RepositoryAccess & { error?: string };
  if (!res.ok) throw new Error(payload.error ?? "Could not load repository access");
  return payload;
}

async function fetchRepositoryAudit(repoKey: string): Promise<AuditEvent[]> {
  const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/audit?limit=20`, {
    cache: "no-store",
  });
  const payload = (await res.json()) as { events?: AuditEvent[]; error?: string };
  if (!res.ok) throw new Error(payload.error ?? "Could not load activity");
  return payload.events ?? [];
}

async function fetchGitHubConnection(): Promise<GitHubConnectionState> {
  const res = await fetch("/api/github/connection", { cache: "no-store" });
  const payload = (await res.json()) as { connection?: GitHubConnectionState; error?: string };
  if (!res.ok || !payload.connection) throw new Error(payload.error ?? "Could not load GitHub connection");
  return payload.connection;
}

async function fetchAutomation(repoKey: string): Promise<RepositoryAutomationState> {
  const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/automation`, {
    cache: "no-store",
  });
  const payload = (await res.json()) as {
    automation?: RepositoryAutomationState;
    error?: string;
  };
  if (!res.ok || !payload.automation) {
    throw new Error(payload.error ?? "Could not load automation state");
  }
  return payload.automation;
}

async function setAutomationEnabled(
  repoKey: string,
  enabled: boolean,
): Promise<RepositoryAutomationState> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/automation/${
      enabled ? "enable" : "disable"
    }`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: enabled ? JSON.stringify({ provider: "codex_app_server" }) : undefined,
    },
  );
  const payload = (await res.json()) as {
    automation?: RepositoryAutomationState;
    error?: string;
  };
  if (!res.ok || !payload.automation) {
    throw new Error(payload.error ?? "Could not update automation");
  }
  return payload.automation;
}

interface RemoteExecutionPolicy {
  remoteExecutionAllowed: boolean;
  allowedRunnerIds?: string[];
  allowedSandboxProviders?: string[];
  allowedCodingAssistantProviders?: string[];
  requireTrustedRunner?: boolean;
  secretScopesAllowed?: string[];
}

interface SandboxPolicy {
  sandboxExecutionAllowed: boolean;
  sandboxProvider?: string | null;
  sandboxProviderLabel?: string;
  sandboxProviderReadiness?: SandboxProviderReadiness;
}

interface SandboxProviderReadiness {
  configured?: boolean;
  ready?: boolean;
  status?: string;
  reason?: string | null;
  provider?: string | null;
  label?: string;
  credential?: string;
  workspaceMode?: string;
  credentialMode?: string;
  egressMode?: string;
  operations?: OpenSandboxOperations;
}

interface OpenSandboxOperations {
  provider?: string;
  lastSmokeStatus?: "passed" | "failed" | "never_run" | "running" | string;
  lastSmokeAt?: string;
  reasonCode?: string;
  cleanupWarning?: boolean;
  workspaceMode?: string;
  lastCleanupStatus?: string;
  lastCleanupAt?: string;
  lastCleanupReasonCode?: string;
}

interface OpenSandboxSmokePayload {
  provider: string;
  status: "passed" | "failed" | string;
  message: string;
  workspaceMode?: string;
  changedFileCount?: number;
  cleanupWarning?: boolean;
  operations?: OpenSandboxOperations;
}

interface SecretReference {
  id: string;
  label: string;
  scope: string;
  source: "environment" | string;
  envName: string;
  configured: boolean;
  lastCheckedAt?: string;
}

interface SecretReferencesPayload {
  secretReferences: SecretReference[];
}

interface PairingTokenPayload {
  pairingToken: string;
  expiresAt: string;
  runnerName: string;
  message: string;
}

type RunnerAction = "approve" | "enable" | "disable" | "revoke" | "rotate-token";

async function fetchRemoteExecutionPolicy(repoKey: string): Promise<RemoteExecutionPolicy> {
  const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/remote-execution`, {
    cache: "no-store",
  });
  const payload = (await res.json()) as { policy?: RemoteExecutionPolicy; error?: string };
  if (!res.ok || !payload.policy) {
    throw new Error(payload.error ?? "Could not load remote execution policy");
  }
  return payload.policy;
}

async function setRemoteExecutionAllowed(
  repoKey: string,
  allowed: boolean,
): Promise<RemoteExecutionPolicy> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/remote-execution/${
      allowed ? "enable" : "disable"
    }`,
    {
      method: "POST",
      cache: "no-store",
    },
  );
  const payload = (await res.json()) as { policy?: RemoteExecutionPolicy; error?: string };
  if (!res.ok || !payload.policy) {
    throw new Error(payload.error ?? "Could not update remote execution policy");
  }
  return payload.policy;
}

async function fetchSandboxPolicy(repoKey: string): Promise<SandboxPolicy> {
  const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/sandbox-policy`, {
    cache: "no-store",
  });
  const payload = (await res.json()) as { policy?: SandboxPolicy; error?: string };
  if (!res.ok || !payload.policy) {
    throw new Error(payload.error ?? "Could not load sandbox execution policy");
  }
  return payload.policy;
}

async function fetchProviderCatalog(repoKey: string): Promise<CodingAssistantProviderCatalog> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/coding-assistants/providers`,
    { cache: "no-store" },
  );
  const payload = (await res.json()) as CodingAssistantProviderCatalog & { error?: string };
  if (!res.ok || !Array.isArray(payload.providers)) {
    throw new Error(payload.error ?? "Could not load provider catalog");
  }
  return payload;
}

async function setSandboxPolicy(repoKey: string, policy: SandboxPolicy): Promise<SandboxPolicy> {
  const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/sandbox-policy`, {
    method: "POST",
    cache: "no-store",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(policy),
  });
  const payload = (await res.json()) as { policy?: SandboxPolicy; error?: string };
  if (!res.ok || !payload.policy) {
    throw new Error(payload.error ?? "Could not update sandbox execution policy");
  }
  return payload.policy;
}

async function runOpenSandboxSmoke(repoKey: string): Promise<OpenSandboxSmokePayload> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/sandbox/opensandbox/smoke`,
    {
      method: "POST",
      cache: "no-store",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({}),
    },
  );
  const payload = (await res.json()) as {
    smoke?: OpenSandboxSmokePayload;
    message?: string;
    error?: string;
  };
  if (!res.ok || !payload.smoke) {
    throw new Error(payload.message ?? payload.error ?? "Could not run OpenSandbox smoke");
  }
  return payload.smoke;
}

async function fetchSecretReferences(repoKey: string): Promise<SecretReference[]> {
  const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/secret-references`, {
    cache: "no-store",
  });
  const payload = (await res.json()) as SecretReferencesPayload & { error?: string };
  if (!res.ok) {
    throw new Error(payload.error ?? "Could not load secret references");
  }
  return payload.secretReferences ?? [];
}

async function createPairingToken(): Promise<PairingTokenPayload> {
  const res = await fetch("/api/runners/pairing-tokens", {
    method: "POST",
    cache: "no-store",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      name: "Remote runner",
      expiresInMinutes: 15,
      capabilityHint: { codexAppServer: true, validation: true },
    }),
  });
  const payload = (await res.json()) as Partial<PairingTokenPayload> & { error?: string };
  if (!res.ok || !payload.pairingToken || !payload.expiresAt || !payload.runnerName) {
    throw new Error(payload.error ?? "Could not create pairing token");
  }
  return {
    pairingToken: payload.pairingToken,
    expiresAt: payload.expiresAt,
    runnerName: payload.runnerName,
    message: payload.message ?? "Copy this token now. It will not be shown again.",
  };
}

interface HarnessStatus {
  running: boolean;
  online?: boolean;
  paused?: boolean;
  mode?: string;
  intervalMs?: number;
  activeRuns?: number;
  staleRuns?: number;
  retryScheduled?: number;
  limits?: {
    maxClaimsPerTick?: number;
    maxClaimsPerRepo?: number;
    maxConcurrentRuns?: number;
  };
  providerReadiness?: {
    runnableProvider?: string;
    providers?: CodingAssistantProviderStatus[];
  };
  runners?: {
    localService: RunnerStatusRow;
    remote: RunnerStatusRow[];
  };
  lastHeartbeatAt?: string;
  lastDispatch?: {
    at?: string;
    repo?: string;
    task?: string;
    runId?: string;
  } | null;
  lastReconciliation?: {
    at?: string;
    reconciled?: number;
    stale?: number;
    message?: string;
  } | null;
  lastError?: {
    at?: string;
    repo?: string;
    task?: string;
    message?: string;
  } | null;
  recentDecisions?: HarnessDecision[];
}

async function fetchHarnessStatus(): Promise<HarnessStatus> {
  const res = await fetch("/api/harness/status", { cache: "no-store" });
  const payload = (await res.json()) as { harness?: HarnessStatus; error?: string };
  if (!res.ok || !payload.harness) {
    throw new Error(payload.error ?? "Could not load Harness status");
  }
  return payload.harness;
}

async function postHarnessAction(
  repoKey: string,
  action: "pause" | "resume" | "tick" | "reconcile",
): Promise<HarnessStatus> {
  const res = await fetch(`/api/harness/${action}?repoKey=${encodeURIComponent(repoKey)}`, {
    method: "POST",
    cache: "no-store",
  });
  const payload = (await res.json()) as { harness?: HarnessStatus; error?: string } & HarnessStatus;
  const harness = payload.harness ?? payload;
  if (!res.ok || !harness) {
    throw new Error(payload.error ?? "Could not update Harness");
  }
  return harness;
}

async function postRunnerAction(
  runnerId: string,
  action: RunnerAction,
): Promise<{ runner: RunnerStatusRow; runnerToken?: string }> {
  const res = await fetch(`/api/runners/${encodeURIComponent(runnerId)}/${action}`, {
    method: "POST",
    cache: "no-store",
  });
  const payload = (await res.json()) as {
    runner?: RunnerStatusRow;
    runnerToken?: string;
    error?: string;
  };
  if (!res.ok || !payload.runner) {
    throw new Error(payload.error ?? "Could not update runner");
  }
  return { runner: payload.runner, runnerToken: payload.runnerToken };
}

function AccessPanel({ access }: { access: RepositoryAccess | null }) {
  const permissions = access?.permissions ?? {};
  const highlighted = [
    "task.run_codex",
    "review.approve",
    "pull_request.open",
    "harness.pause",
    "automation.enable",
  ] as const;

  return (
    <div className="rounded-[10px] border bg-card shadow-[var(--elevation-card)]">
      <div className="flex items-start justify-between gap-3 p-3">
        <div className="flex min-w-0 items-start gap-3">
          <span className="grid h-8 w-8 place-items-center rounded-[8px] bg-muted text-foreground">
            <ShieldCheck className="h-4 w-4" />
          </span>
          <div className="min-w-0">
            <div className="text-sm font-medium">Access</div>
            <div className="text-xs text-muted-foreground">
              Your role: {roleLabel(access?.role)}
            </div>
            <div className="mt-1 text-xs text-muted-foreground">
              {permissionSummary(access)}
            </div>
          </div>
        </div>
      </div>
      <div className="flex flex-wrap gap-1.5 border-t px-3 py-3 text-xs">
        {highlighted.map((permission) => (
          <span
            key={permission}
            className={cn(
              "rounded-[8px] border px-2 py-0.5",
              permissions[permission]
                ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300"
                : "text-muted-foreground",
            )}
          >
            {permissionLabel(permission)}
          </span>
        ))}
      </div>
    </div>
  );
}

function ActivityPanel({ events }: { events: AuditEvent[] }) {
  return (
    <div className="rounded-[10px] border bg-card shadow-[var(--elevation-card)]">
      <div className="flex items-start justify-between gap-3 p-3">
        <div className="flex min-w-0 items-start gap-3">
          <span className="grid h-8 w-8 place-items-center rounded-[8px] bg-muted text-foreground">
            <Activity className="h-4 w-4" />
          </span>
          <div className="min-w-0">
            <div className="text-sm font-medium">Activity</div>
            <div className="text-xs text-muted-foreground">Recent repository events.</div>
          </div>
        </div>
      </div>
      <div className="border-t px-3 py-3">
        {events.length > 0 ? (
          <ol className="space-y-3">
            {events.slice(0, 8).map((event) => (
              <li key={event.id} className="border-l pl-3 text-xs">
                <div className="flex flex-wrap items-center gap-2">
                  <span>{event.summary}</span>
                  <span className="rounded-[7px] border px-1.5 py-0.5 text-[10px] text-muted-foreground">
                    {auditResultLabel(event.result)}
                  </span>
                </div>
                <div className="mt-0.5 font-mono text-[10px] text-muted-foreground">
                  {formatAuditTime(event.at)}
                </div>
              </li>
            ))}
          </ol>
        ) : (
          <div className="text-xs text-muted-foreground">No repository activity recorded yet.</div>
        )}
      </div>
    </div>
  );
}

function AutomationIntegration({
  repoKey,
  access,
}: {
  repoKey: string;
  access: RepositoryAccess | null;
}) {
  const [automation, setAutomation] = useState<RepositoryAutomationState | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetchAutomation(repoKey)
      .then((nextAutomation) => {
        if (cancelled) return;
        setAutomation(nextAutomation);
      })
      .catch((err: unknown) => {
        if (!cancelled) setError(err instanceof Error ? err.message : "Could not load automation");
      });
    return () => {
      cancelled = true;
    };
  }, [repoKey]);

  const toggleAutomation = async () => {
    const nextEnabled = !automation?.enabled;
    setPending(true);
    setError(null);
    try {
      const nextAutomation = await setAutomationEnabled(repoKey, nextEnabled);
      setAutomation(nextAutomation);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not update automation");
    } finally {
      setPending(false);
    }
  };

  const permission = automation?.enabled ? "automation.disable" : "automation.enable";
  const blockedReason = disabledReason(access, permission);

  return (
    <div className="rounded-[10px] border bg-card shadow-[var(--elevation-card)]">
      <div className="flex items-start justify-between gap-3 p-3">
        <div className="flex min-w-0 items-start gap-3">
          <span className="grid h-8 w-8 place-items-center rounded-[8px] bg-muted text-foreground">
            <Bot className="h-4 w-4" />
          </span>
          <div className="min-w-0">
            <div className="text-sm font-medium">Codex Automation</div>
            {error && (
              <div className="mt-2 text-xs text-amber-700 dark:text-amber-300">{error}</div>
            )}
          </div>
        </div>
        <button
          onClick={toggleAutomation}
          disabled={pending || automation == null || Boolean(blockedReason)}
          title={blockedReason}
          className={cn(
            "shrink-0 rounded-[8px] border px-2.5 py-1 text-xs transition-colors disabled:cursor-not-allowed disabled:opacity-50",
            automation?.enabled
              ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-600 hover:bg-emerald-500/15 dark:text-emerald-400"
              : "hover:bg-accent",
          )}
        >
          {pending ? "Updating..." : automation?.enabled ? "Disable" : "Enable"}
        </button>
      </div>
    </div>
  );
}

function HarnessPanel({
  repoKey,
  access,
}: {
  repoKey: string;
  access: RepositoryAccess | null;
}) {
  const [status, setStatus] = useState<HarnessStatus | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pendingAction, setPendingAction] = useState<"pause" | "resume" | "tick" | "reconcile" | null>(null);
  const [pendingRunnerAction, setPendingRunnerAction] = useState<string | null>(null);
  const [remotePolicy, setRemotePolicy] = useState<RemoteExecutionPolicy | null>(null);
  const [pendingRemotePolicy, setPendingRemotePolicy] = useState(false);
  const [sandboxPolicy, setSandboxPolicyState] = useState<SandboxPolicy | null>(null);
  const [providerCatalog, setProviderCatalog] =
    useState<CodingAssistantProviderCatalog | null>(null);
  const [pendingSandboxPolicy, setPendingSandboxPolicy] = useState(false);
  const [pendingSandboxSmoke, setPendingSandboxSmoke] = useState(false);
  const [secretReferences, setSecretReferences] = useState<SecretReference[]>([]);
  const [oneTimeToken, setOneTimeToken] = useState<PairingTokenPayload | { runnerToken: string } | null>(null);

  useEffect(() => {
    let cancelled = false;

    const refresh = () => {
      Promise.all([
        fetchHarnessStatus(),
        fetchRemoteExecutionPolicy(repoKey),
        fetchSandboxPolicy(repoKey),
        fetchProviderCatalog(repoKey).catch(() => null),
        fetchSecretReferences(repoKey),
      ]).then(
        ([
          nextStatus,
          nextPolicy,
          nextSandboxPolicy,
          nextProviderCatalog,
          nextSecretReferences,
        ]) => {
          if (cancelled) return;
          setStatus(nextStatus);
          setRemotePolicy(nextPolicy);
          setSandboxPolicyState(nextSandboxPolicy);
          setProviderCatalog(nextProviderCatalog);
          setSecretReferences(nextSecretReferences);
          setError(null);
        },
      )
        .catch((err: unknown) => {
          if (!cancelled) setError(err instanceof Error ? err.message : "Could not load Harness");
        });
    };

    refresh();
    const interval = window.setInterval(refresh, 5000);
    return () => {
      cancelled = true;
      window.clearInterval(interval);
    };
  }, [repoKey]);

  const runAction = async (action: "pause" | "resume" | "tick" | "reconcile") => {
    setPendingAction(action);
    setError(null);
    try {
      const nextStatus = await postHarnessAction(repoKey, action);
      setStatus(nextStatus);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not update Harness");
    } finally {
      setPendingAction(null);
    }
  };

  const runRunnerAction = async (runner: RunnerStatusRow, action: RunnerAction) => {
    const key = `${runner.id}:${action}`;
    setPendingRunnerAction(key);
    setError(null);
    try {
      const result = await postRunnerAction(runner.id, action);
      if (result.runnerToken) {
        setOneTimeToken({ runnerToken: result.runnerToken });
      }
      setStatus(await fetchHarnessStatus());
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not update runner");
    } finally {
      setPendingRunnerAction(null);
    }
  };

  const pairRunner = async () => {
    setPendingRunnerAction("pair");
    setError(null);
    try {
      setOneTimeToken(await createPairingToken());
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not create pairing token");
    } finally {
      setPendingRunnerAction(null);
    }
  };

  const toggleRemotePolicy = async () => {
    setPendingRemotePolicy(true);
    setError(null);
    try {
      const nextPolicy = await setRemoteExecutionAllowed(
        repoKey,
        !(remotePolicy?.remoteExecutionAllowed ?? false),
      );
      setRemotePolicy(nextPolicy);
      window.dispatchEvent(new CustomEvent("symphonia:readinessUpdated"));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not update remote execution policy");
    } finally {
      setPendingRemotePolicy(false);
    }
  };

  const toggleSandboxPolicy = async () => {
    setPendingSandboxPolicy(true);
    setError(null);
    try {
      const allowed = !(sandboxPolicy?.sandboxExecutionAllowed ?? false);
      const nextPolicy = await setSandboxPolicy(repoKey, {
        sandboxExecutionAllowed: allowed,
        sandboxProvider: allowed ? (sandboxPolicy?.sandboxProvider ?? "opensandbox") : null,
      });
      setSandboxPolicyState(nextPolicy);
      window.dispatchEvent(new CustomEvent("symphonia:readinessUpdated"));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not update sandbox execution policy");
    } finally {
      setPendingSandboxPolicy(false);
    }
  };

  const smokeOpenSandbox = async () => {
    setPendingSandboxSmoke(true);
    setError(null);
    try {
      const smoke = await runOpenSandboxSmoke(repoKey);
      setSandboxPolicyState((current) =>
        current
          ? {
              ...current,
              sandboxProviderReadiness: {
                ...(current.sandboxProviderReadiness ?? {}),
                operations:
                  smoke.operations ?? current.sandboxProviderReadiness?.operations,
              },
            }
          : current,
      );
      setSandboxPolicyState(await fetchSandboxPolicy(repoKey));
      window.dispatchEvent(new CustomEvent("symphonia:readinessUpdated"));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not run OpenSandbox smoke");
      try {
        setSandboxPolicyState(await fetchSandboxPolicy(repoKey));
        window.dispatchEvent(new CustomEvent("symphonia:readinessUpdated"));
      } catch {
        // Keep the visible smoke error if the follow-up refresh fails.
      }
    } finally {
      setPendingSandboxSmoke(false);
    }
  };

  const providers = providerCatalog?.providers ?? status?.providerReadiness?.providers ?? [];
  const runnableProvider = providers.find((provider) => provider.id === "codex_app_server");
  const canRunCodex = runnableProvider ? canHarnessRunProvider(runnableProvider) : false;
  const decisionGroups = groupHarnessDecisions(status?.recentDecisions ?? []);
  const statusLabel = harnessStatusLabel(error ? { lastError: { message: error } } : status);
  const statusTone = error ? "warning" : status?.paused ? "neutral" : status?.online && status.running ? "ready" : "neutral";

  return (
    <div className="rounded-[10px] border bg-card shadow-[var(--elevation-card)]">
      <div className="flex items-start justify-between gap-3 p-3">
        <div className="flex min-w-0 items-start gap-3">
          <span className="grid h-8 w-8 place-items-center rounded-[8px] bg-muted text-foreground">
            <Activity className="h-4 w-4" />
          </span>
          <div className="min-w-0">
            <div className="text-sm font-medium">Harness</div>
            <div className="text-xs text-muted-foreground">
              Local service runner for review-first Codex task work.
            </div>
          </div>
        </div>
        <StatusPill tone={statusTone} label={statusLabel} />
      </div>

      <div className="border-t px-3 py-3">
        {error ? (
          <div className="text-xs text-amber-700 dark:text-amber-300">{error}</div>
        ) : (
          <div className="grid gap-2 sm:grid-cols-3">
            <HarnessMetric label="Mode" value={status?.mode ?? "local_service"} />
            <HarnessMetric
              label="Heartbeat"
              value={formatShortDate(status?.lastHeartbeatAt) ?? "No tick yet"}
            />
            <HarnessMetric
              label="Interval"
              value={status?.intervalMs ? `${Math.round(status.intervalMs / 1000)}s` : "Loading"}
            />
            <HarnessMetric
              label="Last reconcile"
              value={formatShortDate(status?.lastReconciliation?.at) ?? "Not yet"}
            />
          </div>
        )}
      </div>

      <div className="border-t px-3 py-3">
        <div className="grid gap-2 sm:grid-cols-3">
          <HarnessMetric label="Active runs" value={String(status?.activeRuns ?? 0)} />
          <HarnessMetric label="Stale runs" value={String(status?.staleRuns ?? 0)} />
          <HarnessMetric label="Retries scheduled" value={String(status?.retryScheduled ?? 0)} />
        </div>
        <div className="mt-3 flex flex-wrap gap-1.5">
          {status?.paused ? (
            <HarnessActionButton
              label="Resume Harness"
              icon={<Play className="h-3.5 w-3.5" />}
              pending={pendingAction === "resume"}
              disabled={pendingAction != null || !canAccess(access, "harness.resume")}
              disabledReason={disabledReason(access, "harness.resume")}
              onClick={() => runAction("resume")}
            />
          ) : (
            <HarnessActionButton
              label="Pause Harness"
              icon={<Pause className="h-3.5 w-3.5" />}
              pending={pendingAction === "pause"}
              disabled={pendingAction != null || !canAccess(access, "harness.pause")}
              disabledReason={disabledReason(access, "harness.pause")}
              onClick={() => runAction("pause")}
            />
          )}
          <HarnessActionButton
            label="Run check now"
            icon={<RefreshCw className="h-3.5 w-3.5" />}
            pending={pendingAction === "tick"}
            disabled={pendingAction != null || !canAccess(access, "harness.tick")}
            disabledReason={disabledReason(access, "harness.tick")}
            onClick={() => runAction("tick")}
          />
          <HarnessActionButton
            label="Reconcile"
            icon={<Activity className="h-3.5 w-3.5" />}
            pending={pendingAction === "reconcile"}
            disabled={pendingAction != null || !canAccess(access, "harness.reconcile")}
            disabledReason={disabledReason(access, "harness.reconcile")}
            onClick={() => runAction("reconcile")}
          />
        </div>
      </div>

      <RunnerCapacitySection
        runners={status?.runners}
        access={access}
        remotePolicy={remotePolicy}
        sandboxPolicy={sandboxPolicy}
        pendingRemotePolicy={pendingRemotePolicy}
        pendingSandboxPolicy={pendingSandboxPolicy}
        pendingSandboxSmoke={pendingSandboxSmoke}
        onToggleRemotePolicy={toggleRemotePolicy}
        onToggleSandboxPolicy={toggleSandboxPolicy}
        onSmokeOpenSandbox={smokeOpenSandbox}
        pendingAction={pendingRunnerAction}
        onAction={runRunnerAction}
        onPairRunner={pairRunner}
        oneTimeToken={oneTimeToken}
        secretReferences={secretReferences}
      />

      <div className="border-t px-3 py-3">
        <div className="mb-2 text-[11px] font-medium uppercase text-muted-foreground">
          Limits
        </div>
        <div className="grid gap-2 sm:grid-cols-3">
          <HarnessMetric
            label="Per tick"
            value={String(status?.limits?.maxClaimsPerTick ?? 1)}
          />
          <HarnessMetric
            label="Per repository"
            value={String(status?.limits?.maxClaimsPerRepo ?? 1)}
          />
          <HarnessMetric
            label="Concurrent"
            value={String(status?.limits?.maxConcurrentRuns ?? 1)}
          />
        </div>
      </div>

      <div className="border-t px-3 py-3">
        <div className="mb-2 flex items-center justify-between gap-2">
          <div className="text-[11px] font-medium uppercase text-muted-foreground">
            Coding Assistant Providers
          </div>
          <StatusPill
            tone={canRunCodex ? "ready" : "warning"}
            label={canRunCodex ? "Codex ready" : "Codex setup"}
          />
        </div>
        <div className="space-y-2">
          {providers.map((provider) => (
            <ProviderContractRow key={provider.id} provider={provider} />
          ))}
        </div>
      </div>

      <div className="border-t px-3 py-3">
        <div className="mb-2 text-[11px] font-medium uppercase text-muted-foreground">
          Last dispatch
        </div>
        {status?.lastDispatch ? (
          <div className="text-xs text-muted-foreground">
            <span className="font-mono text-foreground">{status.lastDispatch.task}</span>
            <span> started </span>
            <span>{formatShortDate(status.lastDispatch.at) ?? "recently"}</span>
          </div>
        ) : (
          <div className="text-xs text-muted-foreground">No daemon dispatch recorded.</div>
        )}
        {status?.lastError?.message && (
          <div className="mt-2 text-xs text-amber-700 dark:text-amber-300">
            {status.lastError.message}
          </div>
        )}
      </div>

      <div className="border-t px-3 py-3">
        <div className="mb-2 text-[11px] font-medium uppercase text-muted-foreground">
          Recent decisions
        </div>
        {(status?.recentDecisions ?? []).length > 0 ? (
          <div className="space-y-3">
            <HarnessDecisionGroup label="Dispatched" decisions={decisionGroups.dispatch} />
            <HarnessDecisionGroup label="Skipped" decisions={decisionGroups.skip} />
            <HarnessDecisionGroup label="Errored" decisions={decisionGroups.error} />
            <HarnessDecisionGroup label="Reconciled" decisions={decisionGroups.reconcile} />
            <HarnessDecisionGroup label="Retried" decisions={decisionGroups.retry} />
            <HarnessDecisionGroup label="Paused" decisions={decisionGroups.pause} />
          </div>
        ) : (
          <div className="text-xs text-muted-foreground">No Harness decisions yet.</div>
        )}
      </div>
    </div>
  );
}

function RunnerCapacitySection({
  runners,
  access,
  remotePolicy,
  sandboxPolicy,
  pendingRemotePolicy,
  pendingSandboxPolicy,
  pendingSandboxSmoke,
  onToggleRemotePolicy,
  onToggleSandboxPolicy,
  onSmokeOpenSandbox,
  pendingAction,
  onAction,
  onPairRunner,
  oneTimeToken,
  secretReferences,
}: {
  runners?: HarnessStatus["runners"];
  access: RepositoryAccess | null;
  remotePolicy: RemoteExecutionPolicy | null;
  sandboxPolicy: SandboxPolicy | null;
  pendingRemotePolicy: boolean;
  pendingSandboxPolicy: boolean;
  pendingSandboxSmoke: boolean;
  onToggleRemotePolicy: () => void;
  onToggleSandboxPolicy: () => void;
  onSmokeOpenSandbox: () => void;
  pendingAction: string | null;
  onAction: (runner: RunnerStatusRow, action: RunnerAction) => void;
  onPairRunner: () => void;
  oneTimeToken: PairingTokenPayload | { runnerToken: string } | null;
  secretReferences: SecretReference[];
}) {
  const localService = runners?.localService;
  const remote = runners?.remote ?? [];
  const remoteAllowed = remotePolicy?.remoteExecutionAllowed === true;
  const sandboxAllowed = sandboxPolicy?.sandboxExecutionAllowed === true;
  const sandboxReadiness = sandboxPolicy?.sandboxProviderReadiness;
  const sandboxOperations = sandboxReadiness?.operations;
  const sandboxProvider = sandboxReadiness?.provider ?? sandboxPolicy?.sandboxProvider;
  const sandboxProviderAllowed =
    !!sandboxProvider && (remotePolicy?.allowedSandboxProviders ?? []).includes(sandboxProvider);
  const policyDisabledReason = disabledReason(access, "repository.configure");
  const sandboxDisabledReason = disabledReason(access, "sandbox.configure");
  const smokeDisabledReason = disabledReason(access, "sandbox.configure");

  return (
    <div className="border-t px-3 py-3">
      <div className="mb-2 flex items-center justify-between gap-2">
        <div className="text-[11px] font-medium uppercase text-muted-foreground">
          Execution capacity
        </div>
        {localService && (
          <StatusPill
            tone={runnerStatusTone(localService)}
            label={runnerStatusLabel(localService)}
          />
        )}
      </div>

      <div className="space-y-2">
        {localService ? (
          <RunnerRow
            runner={localService}
            access={access}
            pendingAction={pendingAction}
            onAction={onAction}
          />
        ) : (
          <div className="text-xs text-muted-foreground">Local service capacity is loading.</div>
        )}

        <div className="pt-1 text-[11px] font-medium uppercase text-muted-foreground">
          Remote runners
        </div>
        {remote.length > 0 ? (
          remote.map((runner) => (
            <RunnerRow
              key={runner.id}
              runner={runner}
              access={access}
              remoteAllowed={remoteAllowed}
              pendingAction={pendingAction}
              onAction={onAction}
            />
          ))
        ) : (
          <div className="rounded-[8px] border bg-background/60 p-2.5 text-xs text-muted-foreground">
            No remote runners connected.
          </div>
        )}

        <div className="rounded-[8px] border bg-background/60 p-2.5 text-xs">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <div className="flex items-center gap-1.5 font-medium">
                <KeyRound className="h-3.5 w-3.5 text-muted-foreground" />
                <span>Runner trust</span>
              </div>
              <div className="mt-1 text-muted-foreground">
                Pairing tokens are shown once. New runners start pending approval.
              </div>
            </div>
            <button
              type="button"
              className="inline-flex h-7 shrink-0 items-center gap-1 rounded-[7px] border px-2 text-muted-foreground transition hover:bg-muted disabled:cursor-not-allowed disabled:opacity-60"
              disabled={pendingAction === "pair" || !canAccess(access, "runner.pair")}
              title={disabledReason(access, "runner.pair")}
              onClick={onPairRunner}
            >
              <KeyRound className="h-3 w-3" />
              {pendingAction === "pair" ? "Creating" : "Pair runner"}
            </button>
          </div>
          {oneTimeToken && (
            <div className="mt-2 rounded-[7px] border bg-muted/40 p-2 font-mono text-[11px] text-foreground">
              {"pairingToken" in oneTimeToken
                ? oneTimeToken.pairingToken
                : oneTimeToken.runnerToken}
            </div>
          )}
        </div>

        <div className="rounded-[8px] border bg-background/60 p-2.5 text-xs">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <div className="flex items-center gap-1.5 font-medium">
                <ShieldCheck className="h-3.5 w-3.5 text-muted-foreground" />
                <span>
                  {remoteAllowed ? "Remote execution enabled" : "Remote execution disabled"}
                </span>
              </div>
              <div className="mt-1 text-muted-foreground">
                Only owners and maintainers can change this repository policy.
              </div>
            </div>
            <button
              type="button"
              className="inline-flex h-7 shrink-0 items-center gap-1 rounded-[7px] border px-2 text-muted-foreground transition hover:bg-muted disabled:cursor-not-allowed disabled:opacity-60"
              disabled={
                pendingRemotePolicy || !canAccess(access, "repository.configure")
              }
              title={policyDisabledReason}
              onClick={onToggleRemotePolicy}
            >
              {remoteAllowed ? <Pause className="h-3 w-3" /> : <Play className="h-3 w-3" />}
              {pendingRemotePolicy ? "Updating" : remoteAllowed ? "Disable" : "Enable"}
            </button>
          </div>
        </div>

        <div className="rounded-[8px] border bg-background/60 p-2.5 text-xs">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <div className="flex items-center gap-1.5 font-medium">
                <ShieldCheck className="h-3.5 w-3.5 text-muted-foreground" />
                <span>
                  {sandboxAllowed ? "Sandbox execution enabled" : "Sandbox execution disabled"}
                </span>
              </div>
              <div className="mt-1 text-muted-foreground">
                Provider: {sandboxPolicy?.sandboxProviderLabel ?? sandboxReadiness?.label ?? "Not configured"} · Mode: Manual only
              </div>
              <div className="mt-1 flex flex-wrap gap-1.5">
                <StatusPill
                  tone={sandboxReadiness?.ready ? "ready" : sandboxReadiness?.configured ? "warning" : "neutral"}
                  label={
                    sandboxReadiness?.ready
                      ? "Configured"
                      : sandboxReadiness?.configured
                        ? "Blocked"
                        : "Missing credential"
                  }
                />
                <StatusPill
                  tone={sandboxProviderAllowed ? "ready" : "neutral"}
                  label={sandboxProviderAllowed ? "Allowed for repository" : "Not allowlisted"}
                />
                {sandboxReadiness?.workspaceMode === "source_bundle" && (
                  <StatusPill tone="neutral" label="Source bundle" />
                )}
                {sandboxReadiness?.credentialMode === "source_bundle" && (
                  <StatusPill tone="neutral" label="No Git credentials" />
                )}
                <StatusPill
                  tone={sandboxSmokeTone(sandboxOperations)}
                  label={sandboxSmokeLabel(sandboxOperations)}
                />
                {sandboxOperations?.cleanupWarning && (
                  <StatusPill tone="warning" label="Cleanup warning" />
                )}
              </div>
              {sandboxOperations?.lastSmokeAt && (
                <div className="mt-1 text-muted-foreground">
                  Last smoke: {formatShortDate(sandboxOperations.lastSmokeAt)}
                  {sandboxOperations.reasonCode ? ` · ${sandboxOperations.reasonCode}` : ""}
                </div>
              )}
              {sandboxAllowed && (
                <div className="mt-1 text-muted-foreground">
                  Symphonia still imports and validates sandbox changes locally before review.
                </div>
              )}
            </div>
            <div className="flex shrink-0 flex-col gap-1 sm:flex-row">
              <button
                type="button"
                className="inline-flex h-7 items-center gap-1 rounded-[7px] border px-2 text-muted-foreground transition hover:bg-muted disabled:cursor-not-allowed disabled:opacity-60"
                disabled={pendingSandboxSmoke || !canAccess(access, "sandbox.configure")}
                title={smokeDisabledReason}
                onClick={onSmokeOpenSandbox}
              >
                <RefreshCw className="h-3 w-3" />
                {pendingSandboxSmoke ? "Running" : "Smoke"}
              </button>
              <button
                type="button"
                className="inline-flex h-7 items-center gap-1 rounded-[7px] border px-2 text-muted-foreground transition hover:bg-muted disabled:cursor-not-allowed disabled:opacity-60"
                disabled={pendingSandboxPolicy || !canAccess(access, "sandbox.configure")}
                title={sandboxDisabledReason}
                onClick={onToggleSandboxPolicy}
              >
                {sandboxAllowed ? <Pause className="h-3 w-3" /> : <Play className="h-3 w-3" />}
                {pendingSandboxPolicy ? "Updating" : sandboxAllowed ? "Disable" : "Enable"}
              </button>
            </div>
          </div>
        </div>

        <div className="rounded-[8px] border bg-background/60 p-2.5 text-xs">
          <div className="flex items-center gap-1.5 font-medium">
            <KeyRound className="h-3.5 w-3.5 text-muted-foreground" />
            <span>Secret references</span>
          </div>
          <div className="mt-1 text-muted-foreground">
            References are environment-backed metadata. Values are never shown.
          </div>
          <div className="mt-2 space-y-1.5">
            {secretReferences.length > 0 ? (
              secretReferences.map((reference) => (
                <div key={reference.id} className="flex items-center justify-between gap-2 rounded-[7px] border px-2 py-1.5">
                  <div className="min-w-0">
                    <div className="truncate font-medium">{reference.label}</div>
                    <div className="truncate text-muted-foreground">
                      Environment: {reference.envName} · {reference.scope}
                    </div>
                  </div>
                  <StatusPill
                    tone={reference.configured ? "ready" : "warning"}
                    label={reference.configured ? "Configured" : "Missing"}
                  />
                </div>
              ))
            ) : (
              <div className="rounded-[7px] border px-2 py-1.5 text-muted-foreground">
                No secret references configured.
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function RunnerRow({
  runner,
  access,
  remoteAllowed,
  pendingAction,
  onAction,
}: {
  runner: RunnerStatusRow;
  access: RepositoryAccess | null;
  remoteAllowed?: boolean;
  pendingAction: string | null;
  onAction: (runner: RunnerStatusRow, action: RunnerAction) => void;
}) {
  const isRemote = runner.mode === "remote_runner";
  const action = runner.status === "disabled" ? "enable" : "disable";
  const permission = action === "enable" ? "runner.enable" : "runner.disable";
  const blockedReason = isRemote ? disabledReason(access, permission) : undefined;
  const pending = pendingAction === `${runner.id}:${action}`;
  const approveBlockedReason = disabledReason(access, "runner.approve");
  const rotateBlockedReason = disabledReason(access, "runner.rotate_token");
  const revokeBlockedReason = disabledReason(access, "runner.revoke");

  return (
    <div className="rounded-[8px] border bg-background/60 p-2.5 text-xs">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-1.5 font-medium">
            <Activity className="h-3.5 w-3.5 text-muted-foreground" />
            <span>{runner.name}</span>
          </div>
          <div className="mt-1 text-muted-foreground">{runnerCapabilitySummary(runner)}</div>
          <div className="mt-1 text-muted-foreground">{runnerTrustDetail(runner)}</div>
          {isRemote && (
            <div className="mt-1 text-muted-foreground">
              {remoteAllowed
                ? "Remote execution enabled for this repository."
                : "Remote execution disabled for this repository."}
            </div>
          )}
        </div>
        <StatusPill tone={runnerStatusTone(runner)} label={runnerStatusLabel(runner)} />
      </div>

      <div className="mt-2 flex flex-wrap items-center gap-1.5">
        <span className="rounded-[7px] border px-2 py-0.5 text-muted-foreground">
          Capacity {runnerCapacityLabel(runner)}
        </span>
        {isRemote && (
          <>
            {runner.trustState === "pending" && (
              <button
                type="button"
                className="inline-flex h-6 items-center gap-1 rounded-[7px] border px-2 text-muted-foreground transition hover:bg-muted disabled:cursor-not-allowed disabled:opacity-60"
                disabled={pendingAction === `${runner.id}:approve` || Boolean(approveBlockedReason)}
                title={approveBlockedReason}
                onClick={() => onAction(runner, "approve")}
              >
                <Check className="h-3 w-3" />
                {pendingAction === `${runner.id}:approve` ? "Approving" : "Approve"}
              </button>
            )}
            {runner.trustState !== "revoked" && (
              <button
                type="button"
                className="inline-flex h-6 items-center gap-1 rounded-[7px] border px-2 text-muted-foreground transition hover:bg-muted disabled:cursor-not-allowed disabled:opacity-60"
                disabled={pending || Boolean(blockedReason)}
                title={blockedReason}
                onClick={() => onAction(runner, action)}
              >
                {action === "enable" ? <Play className="h-3 w-3" /> : <Pause className="h-3 w-3" />}
                {pending ? "Updating" : action === "enable" ? "Enable" : "Disable"}
              </button>
            )}
            {runner.trustState !== "revoked" && (
              <button
                type="button"
                className="inline-flex h-6 items-center gap-1 rounded-[7px] border px-2 text-muted-foreground transition hover:bg-muted disabled:cursor-not-allowed disabled:opacity-60"
                disabled={pendingAction === `${runner.id}:rotate-token` || Boolean(rotateBlockedReason)}
                title={rotateBlockedReason}
                onClick={() => onAction(runner, "rotate-token")}
              >
                <RefreshCw className="h-3 w-3" />
                {pendingAction === `${runner.id}:rotate-token` ? "Rotating" : "Rotate token"}
              </button>
            )}
            {runner.trustState !== "revoked" && (
              <button
                type="button"
                className="inline-flex h-6 items-center gap-1 rounded-[7px] border px-2 text-muted-foreground transition hover:bg-muted disabled:cursor-not-allowed disabled:opacity-60"
                disabled={pendingAction === `${runner.id}:revoke` || Boolean(revokeBlockedReason)}
                title={revokeBlockedReason}
                onClick={() => onAction(runner, "revoke")}
              >
                <Pause className="h-3 w-3" />
                {pendingAction === `${runner.id}:revoke` ? "Revoking" : "Revoke"}
              </button>
            )}
          </>
        )}
      </div>
    </div>
  );
}

function ProviderContractRow({ provider }: { provider: CodingAssistantProviderStatus }) {
  const missing = providerMissingCapabilityLabels(provider);
  const supported = providerSupportedCapabilityLabels(provider);
  const visibleSupported = supported.slice(0, 4);
  const visibleMissing = missing.slice(0, 4);

  return (
    <div className="rounded-[8px] border bg-background/60 p-2.5 text-xs">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-1.5 font-medium">
            <ShieldCheck className="h-3.5 w-3.5 text-muted-foreground" />
            <span>{provider.label}</span>
          </div>
          <div className="mt-1 text-muted-foreground">{provider.reason}</div>
        </div>
        <StatusPill tone={providerStatusTone(provider)} label={providerStatusLabel(provider)} />
      </div>

      <div className="mt-2 flex flex-wrap gap-1.5">
        {canHarnessRunProvider(provider) ? (
          <span className="rounded-[7px] border border-emerald-500/30 bg-emerald-500/10 px-2 py-0.5 text-emerald-600 dark:text-emerald-400">
            Runnable by Harness
          </span>
        ) : (
          <span className="rounded-[7px] border px-2 py-0.5 text-muted-foreground">
            Not runnable by Harness
          </span>
        )}
        {provider.id === "gemini_cli" && (
          <span className="rounded-[7px] border px-2 py-0.5 text-muted-foreground">
            Manual OpenSandbox only
          </span>
        )}
        {visibleSupported.map((capability) => (
          <span key={capability} className="rounded-[7px] border px-2 py-0.5 text-muted-foreground">
            {capability}
          </span>
        ))}
      </div>

      {visibleMissing.length > 0 && (
        <div className="mt-2 text-muted-foreground">
          Missing: {visibleMissing.join(", ")}
          {missing.length > visibleMissing.length ? ` +${missing.length - visibleMissing.length}` : ""}
        </div>
      )}
    </div>
  );
}

function HarnessActionButton({
  label,
  icon,
  pending,
  disabled,
  disabledReason,
  onClick,
}: {
  label: string;
  icon: React.ReactNode;
  pending: boolean;
  disabled: boolean;
  disabledReason?: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      title={disabledReason}
      className="inline-flex items-center gap-1.5 rounded-[8px] border px-2.5 py-1 text-xs transition-colors hover:bg-accent disabled:cursor-not-allowed disabled:opacity-50"
    >
      {icon}
      {pending ? "Working..." : label}
    </button>
  );
}

function permissionLabel(permission: string): string {
  switch (permission) {
    case "task.run_codex":
      return "Run Codex";
    case "review.approve":
      return "Approve";
    case "pull_request.open":
      return "Open PR";
    case "harness.pause":
      return "Harness";
    case "automation.enable":
      return "Automation";
    default:
      return permission;
  }
}

function HarnessDecisionGroup({
  label,
  decisions,
}: {
  label: string;
  decisions: HarnessDecision[];
}) {
  const visible = decisions.slice(-3).reverse();
  if (visible.length === 0) return null;

  return (
    <div>
      <div className="mb-1 text-[10px] font-medium uppercase text-muted-foreground">{label}</div>
      <ul className="space-y-2">
        {visible.map((decision, index) => (
          <li key={`${label}-${decision.at ?? "decision"}-${decision.task ?? index}`} className="text-xs">
            <div className="flex items-center justify-between gap-2">
              <span className="font-mono text-foreground">{decision.task ?? decision.repo ?? "Harness"}</span>
              <span className="text-muted-foreground">{decision.code}</span>
            </div>
            {decision.reason && (
              <div className="mt-0.5 text-muted-foreground">{decision.reason}</div>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}

function HarnessMetric({ label, value }: { label: string; value: string }) {
  return (
    <div className="min-w-0 border-l px-2.5 py-1">
      <div className="text-[11px] text-muted-foreground">{label}</div>
      <div className="truncate text-sm font-medium">{value}</div>
    </div>
  );
}

function StatusPill({
  label,
  tone,
}: {
  label: string;
  tone: "ready" | "warning" | "blocked" | "neutral";
}) {
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

function formatShortDate(value?: string): string | undefined {
  if (!value) return undefined;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function GitHubIntegration({ repoKey }: { repoKey: string }) {
  const [connection, setConnection] = useState<GitHubConnectionState | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetchGitHubConnection()
      .then((nextConnection) => {
        if (cancelled) return;
        setConnection(nextConnection);
      })
      .catch((err: unknown) => {
        if (!cancelled) setError(err instanceof Error ? err.message : "Could not load GitHub");
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const connected = connection?.connected;
  const installed = connection?.installed || (connection?.installedRepositoriesCount ?? 0) > 0;
  const installedCount = connection?.installedRepositoriesCount ?? 0;
  const installUrl = withRepoState(connection?.installationUrl, repoKey);
  const manageUrl = connection?.manageUrl ?? connection?.installationUrl;

  return (
    <div className="rounded-[10px] border bg-card shadow-[var(--elevation-card)]">
      <div className="flex items-start justify-between gap-3 p-3">
        <div className="flex min-w-0 items-start gap-3">
          <span className="grid h-8 w-8 place-items-center rounded-[8px] bg-muted text-foreground">
            <Github className="h-4 w-4" />
          </span>
          <div className="min-w-0">
            <div className="text-sm font-medium">GitHub</div>
            <div className="text-xs text-muted-foreground">
              Choose repositories on GitHub and return to Symphonía automatically.
            </div>
            {!connected && (
              <div className="mt-1 text-xs text-muted-foreground">
                You can still manage local tasks without GitHub.
              </div>
            )}
            {installed && (
              <div className="mt-2 text-xs text-muted-foreground">
                {installedCount} {installedCount === 1 ? "repository" : "repositories"} connected.
              </div>
            )}
            {error && (
              <div className="mt-2 text-xs text-amber-700 dark:text-amber-300">{error}</div>
            )}
          </div>
        </div>
        <div className="flex shrink-0 items-center gap-1.5">
          {installed && (
            <span className="inline-flex items-center gap-1 rounded-[8px] border px-2.5 py-1 text-xs text-muted-foreground">
              <Check className="h-3 w-3" />
              Connected
            </span>
          )}
          {installUrl && !installed && (
            <a
              href={installUrl}
              rel="noreferrer"
              className="rounded-[8px] border px-2.5 py-1 text-xs hover:bg-accent"
            >
              Connect to GitHub
            </a>
          )}
          {manageUrl && installed && (
            <a
              href={manageUrl}
              target="_blank"
              rel="noreferrer"
              className="rounded-[8px] border px-2.5 py-1 text-xs hover:bg-accent"
            >
              Change selection
            </a>
          )}
        </div>
      </div>
    </div>
  );
}

function withRepoState(url: string | undefined, repoKey: string): string | undefined {
  if (!url) return undefined;

  try {
    const next = new URL(url);
    next.searchParams.set("state", repoKey);
    return next.toString();
  } catch {
    const separator = url.includes("?") ? "&" : "?";
    return `${url}${separator}state=${encodeURIComponent(repoKey)}`;
  }
}

function IntegrationRow({
  source,
  name,
  desc,
  repoKey,
}: {
  source: ImportSource;
  name: string;
  desc: string;
  repoKey: string;
}) {
  const [connected, setConnected] = useState(true);
  const [expanded, setExpanded] = useState(false);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [importedIds, setImportedIds] = useState<Set<string>>(new Set());

  const items = useMemo<ExternalIssue[]>(
    () =>
      externalIssues.filter(
        (e) => e.source === source && e.repo === repoKey && !importedIds.has(e.id),
      ),
    [source, repoKey, importedIds],
  );

  const toggleSel = (id: string) => {
    setSelected((s) => {
      const n = new Set(s);
      if (n.has(id)) n.delete(id);
      else n.add(id);
      return n;
    });
  };

  const importSelected = () => {
    setImportedIds((s) => new Set([...s, ...selected]));
    setSelected(new Set());
  };

  const Icon = source === "github" ? Github : LinearMark;

  return (
    <div className="rounded-[10px] border bg-card shadow-[var(--elevation-card)]">
      <div className="flex items-center justify-between gap-3 p-3">
        <div className="flex items-center gap-3 min-w-0">
          <span className="grid h-8 w-8 place-items-center rounded-[8px] bg-muted text-foreground">
            <Icon className="h-4 w-4" />
          </span>
          <div className="min-w-0">
            <div className="text-sm font-medium">{name}</div>
            <div className="text-xs text-muted-foreground">{desc}</div>
          </div>
        </div>
        <div className="flex items-center gap-1.5 shrink-0">
          {connected && items.length > 0 && (
            <button
              onClick={() => setExpanded((v) => !v)}
              className="inline-flex items-center gap-1 rounded-[8px] border px-2 py-1 text-[11px] hover:bg-accent"
              aria-expanded={expanded}
            >
              {expanded ? (
                <ChevronDown className="h-3 w-3" />
              ) : (
                <ChevronRight className="h-3 w-3" />
              )}
              {items.length} to import
            </button>
          )}
          <button
            onClick={() => setConnected((v) => !v)}
            className={cn(
              "rounded-[8px] border px-2.5 py-1 text-xs transition-colors",
              connected
                ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
                : "hover:bg-accent",
            )}
          >
            {connected ? (
              <span className="flex items-center gap-1">
                <Check className="h-3 w-3" /> Connected
              </span>
            ) : (
              "Connect"
            )}
          </button>
        </div>
      </div>

      {connected && expanded && (
        <div className="border-t bg-[var(--card-alt)]">
          {items.length === 0 ? (
            <p className="p-4 text-xs text-muted-foreground text-center">
              Nothing new to import. {name} is up to date with this repository.
            </p>
          ) : (
            <>
              <ul className="divide-y">
                {items.map((it) => {
                  const checked = selected.has(it.id);
                  return (
                    <li
                      key={it.id}
                      className="flex items-start gap-3 px-3 py-2.5"
                    >
                      <input
                        type="checkbox"
                        checked={checked}
                        onChange={() => toggleSel(it.id)}
                        aria-label={`Select ${it.externalKey}`}
                        className="mt-0.5 h-3.5 w-3.5 accent-primary"
                      />
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2 text-[11px] text-muted-foreground">
                          <span className="font-mono">{it.externalKey}</span>
                          <span>·</span>
                          <span>by {it.author}</span>
                          <span>·</span>
                          <span className="tabular-nums">{it.updatedAt}</span>
                          {it.hasConflict && (
                            <span className="inline-flex items-center gap-1 rounded-full border border-amber-500/30 bg-amber-500/10 px-1.5 py-0.5 text-amber-600 dark:text-amber-400">
                              <AlertTriangle className="h-3 w-3" /> conflict
                            </span>
                          )}
                        </div>
                        <p className="mt-0.5 text-sm">{it.title}</p>
                      </div>
                      <button disabled title="Coming soon" className="cursor-not-allowed text-muted-foreground opacity-60" aria-label="Open externally">
                        <ExternalLink className="h-3.5 w-3.5" />
                      </button>
                    </li>
                  );
                })}
              </ul>
              <div className="flex items-center justify-between gap-2 border-t px-3 py-2">
                <span className="text-[11px] text-muted-foreground">
                  {selected.size} selected
                </span>
                <div className="flex items-center gap-1.5">
                  <button
                    disabled title="Coming soon"
                    className="inline-flex cursor-not-allowed items-center gap-1 rounded-[8px] border px-2 py-1 text-[11px] opacity-60"
                  >
                    <Link2 className="h-3 w-3" /> Link to existing
                  </button>
                  <button
                    onClick={importSelected}
                    disabled={selected.size === 0}
                    title={
                      selected.size === 0 ? "Select items to import" : undefined
                    }
                    className="rounded-[8px] bg-primary px-2.5 py-1 text-[11px] text-primary-foreground hover:bg-primary-hover disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    Import {selected.size > 0 ? `${selected.size}` : ""} as task
                    {selected.size === 1 ? "" : "s"}
                  </button>
                </div>
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
}

function SimpleIntegration({
  name,
  desc,
  initialConnected = false,
}: {
  name: string;
  desc: string;
  initialConnected?: boolean;
}) {
  const [enabled, setEnabled] = useState(initialConnected);
  return (
    <div className="flex items-center justify-between rounded-[10px] border bg-card p-3 shadow-[var(--elevation-card)]">
      <div className="min-w-0">
        <div className="text-sm font-medium">{name}</div>
        <div className="text-xs text-muted-foreground">{desc}</div>
      </div>
      <button
        onClick={() => setEnabled((v) => !v)}
        className={cn(
          "rounded-[8px] border px-2.5 py-1 text-xs transition-colors",
          enabled
            ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
            : "hover:bg-accent",
        )}
      >
        {enabled ? (
          <span className="flex items-center gap-1">
            <Check className="h-3 w-3" /> Connected
          </span>
        ) : (
          "Connect"
        )}
      </button>
    </div>
  );
}

function LinearMark({ className }: { className?: string }) {
  // Triangle/arrow stand-in for Linear's wordmark. lucide has no Linear icon.
  return (
    <svg viewBox="0 0 16 16" className={className} fill="none" stroke="currentColor" strokeWidth="1.6">
      <path d="M2 9.5 L8 2 L14 9.5 L8 14 Z" strokeLinejoin="round" />
    </svg>
  );
}

function Section({
  title,
  description,
  children,
}: {
  title: string;
  description: string;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-5">
      <div>
        <h2 className="text-[18px] font-bold tracking-[-0.02em]">{title}</h2>
        <p className="text-sm text-muted-foreground">{description}</p>
      </div>
      <div className="space-y-3">{children}</div>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block space-y-1.5">
      <span className="text-xs font-medium text-muted-foreground">{label}</span>
      {children}
    </label>
  );
}

function ToggleRow({
  label,
  description,
  checked,
  onChange,
  disabled,
  disabledReason,
}: {
  label: string;
  description: string;
  checked: boolean;
  onChange: (v: boolean) => void;
  disabled?: boolean;
  disabledReason?: string;
}) {
  return (
    <div className="flex items-center justify-between gap-4 rounded-[10px] border bg-card p-3">
      <div className="min-w-0">
        <div className="text-sm font-medium">{label}</div>
        <div className="text-xs text-muted-foreground">{description}</div>
      </div>
      <button
        onClick={() => onChange(!checked)}
        disabled={disabled}
        title={disabled ? disabledReason : undefined}
        className={cn(
          "relative h-5 w-9 rounded-full transition-colors shrink-0",
          checked ? "bg-primary" : "bg-muted",
          disabled && "cursor-not-allowed opacity-60",
        )}
        aria-pressed={checked}
        aria-label={label}
      >
        <span
          className={cn(
            "absolute top-0.5 h-4 w-4 rounded-full bg-background transition-transform",
            checked ? "translate-x-4" : "translate-x-0.5",
          )}
        />
      </button>
    </div>
  );
}

function SaveBar() {
  return (
    <div className="flex justify-end gap-2 pt-2">
      <button
        disabled
        title="Coming soon"
        className="cursor-not-allowed rounded-[8px] bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground opacity-60 shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)]"
      >
        Save changes
      </button>
    </div>
  );
}
