"use client";

import { useEffect, useMemo, useState } from "react";
import { cn } from "@/lib/utils";
import {
  externalIssues,
  type ExternalIssue,
  type ImportSource,
} from "@/data/mock";
import type { GitHubConnectionState, RepositoryAutomationState } from "@/lib/repository-model";
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
  AlertTriangle,
  Github,
  ExternalLink,
  Link2,
  ChevronRight,
  ChevronDown,
} from "lucide-react";

type SectionId =
  | "profile"
  | "appearance"
  | "notifications"
  | "workspace"
  | "integrations"
  | "security"
  | "billing";

const sections: { id: SectionId; label: string; icon: typeof UserIcon }[] = [
  { id: "profile", label: "Profile", icon: UserIcon },
  { id: "appearance", label: "Appearance", icon: Palette },
  { id: "notifications", label: "Notifications", icon: Bell },
  { id: "workspace", label: "Repository", icon: Building2 },
  { id: "integrations", label: "Integrations", icon: Plug },
  { id: "security", label: "Security", icon: KeyRound },
  { id: "billing", label: "Billing", icon: CreditCard },
];

export function SettingsView({ repoKey }: { repoKey: string }) {
  const [active, setActive] = useState<SectionId>("integrations");
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
              <AutomationIntegration repoKey={repoKey} />
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

function AutomationIntegration({ repoKey }: { repoKey: string }) {
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
          disabled={pending || automation == null}
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
