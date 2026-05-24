"use client";

import { useEffect, useMemo, useState } from "react";
import { cn } from "@/lib/utils";
import { useTheme } from "@/components/theme-provider";
import {
  externalIssues,
  type ExternalIssue,
  type ImportSource,
} from "@/data/mock";
import type {
  GitHubConnectionState,
  RepositoryGitHubState,
} from "@/lib/repository-model";
import {
  User as UserIcon,
  Bell,
  Palette,
  KeyRound,
  Building2,
  Plug,
  CreditCard,
  Check,
  Github,
  ExternalLink,
  AlertTriangle,
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
  { id: "workspace", label: "Workspace", icon: Building2 },
  { id: "integrations", label: "Integrations", icon: Plug },
  { id: "security", label: "Security", icon: KeyRound },
  { id: "billing", label: "Billing", icon: CreditCard },
];

export function SettingsView({ repoKey }: { repoKey: string }) {
  const [active, setActive] = useState<SectionId>("integrations");
  const { theme, toggle } = useTheme();
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
      <header className="flex items-center justify-between border-b px-4 py-2.5">
        <span className="text-sm font-semibold">Settings</span>
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
                  "flex items-center gap-2 rounded-md px-2 py-1.5 text-sm transition-colors text-left",
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

        <div className="md:hidden flex gap-1 overflow-x-auto border-b px-3 py-2">
          {sections.map((s) => (
            <button
              key={s.id}
              onClick={() => setActive(s.id)}
              className={cn(
                "rounded-md px-2.5 py-1 text-xs whitespace-nowrap",
                active === s.id
                  ? "bg-accent text-foreground font-medium"
                  : "text-muted-foreground hover:bg-accent/60",
              )}
            >
              {s.label}
            </button>
          ))}
        </div>

        <main className="flex-1 overflow-y-auto p-6 max-w-3xl">
          {active === "profile" && (
            <Section title="Profile" description="Your name and contact details across the workspace.">
              <div className="flex items-center gap-4">
                <span className="grid h-16 w-16 place-items-center rounded-full bg-rose-500 text-sm font-medium text-white">
                  AM
                </span>
                <div className="space-y-1">
                  <button className="rounded-md border px-3 py-1 text-xs hover:bg-accent">
                    Upload photo
                  </button>
                  <p className="text-xs text-muted-foreground">PNG or JPG, up to 2 MB.</p>
                </div>
              </div>
              <Field label="Full name">
                <input
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  className="w-full rounded-md border bg-background px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
                />
              </Field>
              <Field label="Email">
                <input
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  type="email"
                  className="w-full rounded-md border bg-background px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
                />
              </Field>
              <Field label="Short bio">
                <textarea
                  value={bio}
                  onChange={(e) => setBio(e.target.value)}
                  rows={3}
                  className="w-full rounded-md border bg-background px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring resize-none"
                />
              </Field>
              <SaveBar />
            </Section>
          )}

          {active === "appearance" && (
            <Section title="Appearance" description="Tune the look and density of the interface.">
              <Field label="Theme">
                <div className="grid grid-cols-2 gap-2 max-w-sm">
                  {(["light", "dark"] as const).map((t) => (
                    <button
                      key={t}
                      onClick={() => {
                        if (theme !== t) toggle();
                      }}
                      className={cn(
                        "rounded-md border p-3 text-left transition-colors",
                        theme === t ? "border-primary ring-2 ring-primary/20" : "hover:bg-accent",
                      )}
                    >
                      <div
                        className={cn(
                          "mb-2 h-12 rounded border",
                          t === "dark" ? "bg-zinc-900" : "bg-zinc-50",
                        )}
                      />
                      <span className="text-xs capitalize">{t}</span>
                    </button>
                  ))}
                </div>
              </Field>
              <ToggleRow
                label="Compact density"
                description="Tighter row heights across lists."
                checked={false}
                onChange={() => {}}
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
            <Section title="Workspace" description="Settings that apply to the whole repository.">
              <Field label="Repository alias">
                <input
                  value={workspaceName}
                  onChange={(e) => setWorkspaceName(e.target.value)}
                  className="w-full rounded-md border bg-background px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
                />
              </Field>
              <Field label="Workspace URL">
                <div className="flex items-stretch rounded-md border overflow-hidden">
                  <span className="bg-muted px-3 py-1.5 text-xs text-muted-foreground border-r flex items-center">
                    symphonia.app/
                  </span>
                  <input
                    defaultValue={repoKey.toLowerCase()}
                    className="flex-1 bg-background px-3 py-1.5 text-sm focus:outline-none"
                    aria-label="Workspace URL slug"
                  />
                </div>
              </Field>
              <Field label="Default task prefix">
                <input
                  defaultValue={repoKey}
                  className="w-32 rounded-md border bg-background px-3 py-1.5 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-ring"
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

          {active === "security" && (
            <Section title="Security" description="Protect your account and audit recent activity.">
              <Field label="Change password">
                <div className="space-y-2 max-w-sm">
                  <input
                    type="password"
                    placeholder="Current password"
                    className="w-full rounded-md border bg-background px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
                  />
                  <input
                    type="password"
                    placeholder="New password"
                    className="w-full rounded-md border bg-background px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
                  />
                </div>
              </Field>
              <ToggleRow
                label="Two-factor authentication"
                description="Require a second factor on every sign-in."
                checked={true}
                onChange={() => {}}
              />
            </Section>
          )}

          {active === "billing" && (
            <Section title="Billing" description="Manage your plan, seats and invoices.">
              <div className="rounded-md border p-4">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="text-xs uppercase tracking-wider text-muted-foreground">
                      Current plan
                    </div>
                    <div className="text-lg font-semibold">Business · 12 seats</div>
                    <div className="text-xs text-muted-foreground">
                      Renews May 28, 2026 · $192/mo
                    </div>
                  </div>
                  <button className="rounded-md border px-3 py-1.5 text-xs hover:bg-accent">
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

interface DeviceFlowState {
  deviceCode: string;
  userCode: string;
  verificationUri: string;
  interval: number;
  expiresIn: number;
}

async function fetchGitHubConnection(): Promise<GitHubConnectionState> {
  const res = await fetch("/api/github/connection", { cache: "no-store" });
  const payload = (await res.json()) as { connection?: GitHubConnectionState; error?: string };
  if (!res.ok || !payload.connection) throw new Error(payload.error ?? "Could not load GitHub connection");
  return payload.connection;
}

async function fetchRepositoryGitHub(repoKey: string): Promise<RepositoryGitHubState> {
  const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/github`, {
    cache: "no-store",
  });
  const payload = (await res.json()) as { github?: RepositoryGitHubState; error?: string };
  if (!res.ok || !payload.github) throw new Error(payload.error ?? "Could not load GitHub repository state");
  return payload.github;
}

function GitHubIntegration({ repoKey }: { repoKey: string }) {
  const [connection, setConnection] = useState<GitHubConnectionState | null>(null);
  const [repoState, setRepoState] = useState<RepositoryGitHubState | null>(null);
  const [device, setDevice] = useState<DeviceFlowState | null>(null);
  const [installationId, setInstallationId] = useState("");
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    Promise.all([fetchGitHubConnection(), fetchRepositoryGitHub(repoKey)])
      .then(([nextConnection, nextRepoState]) => {
        if (cancelled) return;
        setConnection(nextConnection);
        setRepoState(nextRepoState);
      })
      .catch((err: unknown) => {
        if (!cancelled) setError(err instanceof Error ? err.message : "Could not load GitHub");
      });
    return () => {
      cancelled = true;
    };
  }, [repoKey]);

  useEffect(() => {
    if (!device) return;
    const timer = window.setTimeout(() => {
      void pollDevice(device);
    }, Math.max(device.interval, 1) * 1000);
    return () => window.clearTimeout(timer);
  }, [device]);

  const startConnection = async () => {
    setPending("connect");
    setError(null);
    try {
      const res = await fetch("/api/github/connect/start", { method: "POST" });
      const payload = (await res.json()) as DeviceFlowState & { error?: string };
      if (!res.ok) throw new Error(payload.error ?? "Could not start GitHub connection");
      setDevice(payload);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not start GitHub connection");
    } finally {
      setPending(null);
    }
  };

  const pollDevice = async (current: DeviceFlowState) => {
    setPending("poll");
    setError(null);
    try {
      const res = await fetch("/api/github/connect/poll", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          deviceCode: current.deviceCode,
          interval: current.interval,
        }),
      });
      const payload = (await res.json()) as {
        connection?: GitHubConnectionState;
        status?: string;
        interval?: number;
        retryAfter?: number;
        error?: string;
      };

      if (res.status === 202) {
        setDevice({ ...current, interval: payload.interval ?? current.interval });
        return;
      }

      if (res.status === 429) {
        setDevice({ ...current, interval: payload.retryAfter ?? current.interval });
        return;
      }

      if (!res.ok || !payload.connection) {
        throw new Error(payload.error ?? "Could not connect GitHub");
      }

      setConnection(payload.connection);
      setDevice(null);
      setRepoState(await fetchRepositoryGitHub(repoKey));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not connect GitHub");
      setDevice(null);
    } finally {
      setPending(null);
    }
  };

  const linkLocalRepo = async () => {
    setPending("link");
    setError(null);
    try {
      const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/github/link`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({}),
      });
      const payload = (await res.json()) as { github?: RepositoryGitHubState; error?: string };
      if (!res.ok || !payload.github) throw new Error(payload.error ?? "Could not link GitHub repo");
      setRepoState((current) => ({
        connection: current?.connection ?? connection ?? { connected: false },
        detectedRemote: payload.github?.detectedRemote ?? current?.detectedRemote,
        link: payload.github?.link ?? null,
      }));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not link GitHub repo");
    } finally {
      setPending(null);
    }
  };

  const completeInstallation = async () => {
    const trimmed = installationId.trim();
    if (!trimmed) return;

    setPending("installation");
    setError(null);
    try {
      const res = await fetch("/api/github/installations/complete", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ installation_id: trimmed }),
      });
      const payload = (await res.json()) as { connection?: GitHubConnectionState; error?: string };
      if (!res.ok || !payload.connection) {
        throw new Error(payload.error ?? "Could not record GitHub installation");
      }
      setConnection(payload.connection);
      setRepoState(await fetchRepositoryGitHub(repoKey));
      setInstallationId("");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not record GitHub installation");
    } finally {
      setPending(null);
    }
  };

  const refreshInstallations = async () => {
    setPending("refresh");
    setError(null);
    try {
      const res = await fetch("/api/github/installations/refresh", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({}),
      });
      const payload = (await res.json()) as { connection?: GitHubConnectionState; error?: string };
      if (!res.ok || !payload.connection) {
        throw new Error(payload.error ?? "Could not refresh GitHub installations");
      }
      setConnection(payload.connection);
      setRepoState(await fetchRepositoryGitHub(repoKey));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not refresh GitHub installations");
    } finally {
      setPending(null);
    }
  };

  const connected = connection?.connected;
  const link = repoState?.link;
  const detected = repoState?.detectedRemote;
  const installed = connection?.installed || (connection?.installedRepositoriesCount ?? 0) > 0;
  const installedCount = connection?.installedRepositoriesCount ?? 0;
  const accessState = repoState?.access?.state;
  const installUrl = withRepoState(connection?.installationUrl, repoKey);
  const manageUrl = connection?.manageUrl ?? connection?.installationUrl;
  const canLink = accessState === "available" || connection?.authMode === "device_user_token";

  return (
    <div className="rounded-md border">
      <div className="flex items-start justify-between gap-3 p-3">
        <div className="flex min-w-0 items-start gap-3">
          <span className="grid h-8 w-8 place-items-center rounded-md bg-muted text-foreground">
            <Github className="h-4 w-4" />
          </span>
          <div className="min-w-0">
            <div className="text-sm font-medium">GitHub</div>
            <div className="text-xs text-muted-foreground">
              Install the Symphonía GitHub App to choose which repositories Symphonía can access.
            </div>
            {!connected && (
              <div className="mt-1 text-xs text-muted-foreground">
                You can still manage local tasks without GitHub.
              </div>
            )}
            {installed && !link && (
              <div className="mt-2 text-xs text-muted-foreground">
                Symphonía is installed on {installedCount}{" "}
                {installedCount === 1 ? "repository" : "repositories"}.
              </div>
            )}
            {detected && (
              <div className="mt-2 text-[11px] text-muted-foreground">
                Detected local repository:{" "}
                <span className="font-mono">
                  {detected.owner}/{detected.name}
                </span>
              </div>
            )}
            {link && (
              <div className="mt-2 text-[11px] text-muted-foreground">
                This workspace is connected to{" "}
                <a
                  href={link.url}
                  target="_blank"
                  rel="noreferrer"
                  className="font-mono hover:text-foreground"
                >
                  {link.owner}/{link.name}
                </a>
                .
              </div>
            )}
            {!link && accessState === "missing" && detected && (
              <div className="mt-2 flex items-start gap-2 text-xs text-amber-700 dark:text-amber-300">
                <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                <span>Symphonía is not installed on this GitHub repository yet.</span>
              </div>
            )}
            {connection?.deviceFallbackEnabled && (
              <div className="mt-3 rounded-md border bg-muted/30 p-3 text-xs">
                <div className="font-medium">Developer option</div>
                <div className="mt-1 text-muted-foreground">
                  Use GitHub device login for local testing.
                </div>
                {device && (
                  <div className="mt-3 rounded-md border bg-background p-3">
                    <div className="font-medium">Authorize Symphonía on GitHub</div>
                    <div className="mt-1 text-muted-foreground">
                      Enter code{" "}
                      <span className="font-mono text-foreground">{device.userCode}</span>
                    </div>
                    <a
                      href={device.verificationUri}
                      target="_blank"
                      rel="noreferrer"
                      className="mt-2 inline-flex items-center gap-1 rounded-md border bg-background px-2 py-1 hover:bg-muted"
                    >
                      Open GitHub <ExternalLink className="h-3 w-3" />
                    </a>
                  </div>
                )}
                {!device && (
                  <button
                    onClick={startConnection}
                    disabled={pending != null}
                    className="mt-2 rounded-md border bg-background px-2.5 py-1 text-xs hover:bg-accent disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    {pending === "connect" ? "Connecting..." : "Connect with device flow"}
                  </button>
                )}
              </div>
            )}
            <div className="mt-3 rounded-md border bg-muted/20 p-3 text-xs">
              <div className="font-medium">Manual recovery</div>
              <div className="mt-1 text-muted-foreground">
                Paste an installation ID if the local callback used the wrong port.
              </div>
              <div className="mt-2 flex flex-col gap-2 sm:flex-row">
                <input
                  value={installationId}
                  onChange={(event) => setInstallationId(event.target.value)}
                  placeholder="Installation ID"
                  className="min-w-0 flex-1 rounded-md border bg-background px-2 py-1 font-mono focus:outline-none focus:ring-2 focus:ring-ring"
                />
                <button
                  onClick={completeInstallation}
                  disabled={!installationId.trim() || pending != null}
                  className="rounded-md border bg-background px-2.5 py-1 hover:bg-accent disabled:cursor-not-allowed disabled:opacity-50"
                >
                  {pending === "installation" ? "Saving..." : "Save installation"}
                </button>
              </div>
              {installed && (
                <button
                  onClick={refreshInstallations}
                  disabled={pending != null}
                  className="mt-2 rounded-md border bg-background px-2.5 py-1 hover:bg-accent disabled:cursor-not-allowed disabled:opacity-50"
                >
                  {pending === "refresh" ? "Refreshing..." : "Refresh GitHub installations"}
                </button>
              )}
            </div>
            {error && (
              <div className="mt-2 text-xs text-amber-700 dark:text-amber-300">{error}</div>
            )}
          </div>
        </div>
        <div className="flex shrink-0 items-center gap-1.5">
          {link ? (
            <span className="inline-flex items-center gap-1 rounded-md border border-emerald-500/30 bg-emerald-500/10 px-2.5 py-1 text-xs text-emerald-600 dark:text-emerald-400">
              <Check className="h-3 w-3" />
              Linked
            </span>
          ) : installed ? (
            <span className="inline-flex items-center gap-1 rounded-md border px-2.5 py-1 text-xs text-muted-foreground">
              <Check className="h-3 w-3" />
              Installed
            </span>
          ) : null}
          {installUrl && !installed && (
            <a
              href={installUrl}
              rel="noreferrer"
              className="rounded-md border px-2.5 py-1 text-xs hover:bg-accent"
            >
              Install GitHub App
            </a>
          )}
          {manageUrl && installed && (
            <a
              href={manageUrl}
              target="_blank"
              rel="noreferrer"
              className="rounded-md border px-2.5 py-1 text-xs hover:bg-accent"
            >
              Manage access
            </a>
          )}
          <button
            onClick={linkLocalRepo}
            disabled={!canLink || pending != null}
            className="rounded-md border px-2.5 py-1 text-xs hover:bg-accent disabled:cursor-not-allowed disabled:opacity-50"
          >
            {pending === "link" ? "Linking..." : link ? "Relink repository" : "Link this repository"}
          </button>
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
    <div className="rounded-md border">
      <div className="flex items-center justify-between gap-3 p-3">
        <div className="flex items-center gap-3 min-w-0">
          <span className="grid h-8 w-8 place-items-center rounded-md bg-muted text-foreground">
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
              className="inline-flex items-center gap-1 rounded-md border px-2 py-1 text-[11px] hover:bg-muted"
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
              "rounded-md border px-2.5 py-1 text-xs transition-colors",
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
        <div className="border-t bg-muted/20">
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
                      <a
                        href="#"
                        onClick={(e) => e.preventDefault()}
                        className="text-muted-foreground hover:text-foreground"
                        aria-label="Open externally"
                      >
                        <ExternalLink className="h-3.5 w-3.5" />
                      </a>
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
                    disabled={selected.size === 0}
                    title={selected.size === 0 ? "Select items to link" : undefined}
                    className="inline-flex items-center gap-1 rounded-md border px-2 py-1 text-[11px] hover:bg-muted disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    <Link2 className="h-3 w-3" /> Link to existing
                  </button>
                  <button
                    onClick={importSelected}
                    disabled={selected.size === 0}
                    title={
                      selected.size === 0 ? "Select items to import" : undefined
                    }
                    className="rounded-md bg-primary text-primary-foreground px-2.5 py-1 text-[11px] hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed"
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
    <div className="flex items-center justify-between rounded-md border p-3">
      <div className="min-w-0">
        <div className="text-sm font-medium">{name}</div>
        <div className="text-xs text-muted-foreground">{desc}</div>
      </div>
      <button
        onClick={() => setEnabled((v) => !v)}
        className={cn(
          "rounded-md border px-2.5 py-1 text-xs transition-colors",
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
        <h2 className="text-lg font-semibold">{title}</h2>
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
}: {
  label: string;
  description: string;
  checked: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <div className="flex items-center justify-between gap-4 rounded-md border p-3">
      <div className="min-w-0">
        <div className="text-sm font-medium">{label}</div>
        <div className="text-xs text-muted-foreground">{description}</div>
      </div>
      <button
        onClick={() => onChange(!checked)}
        className={cn(
          "relative h-5 w-9 rounded-full transition-colors shrink-0",
          checked ? "bg-primary" : "bg-muted",
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
      <button className="rounded-md border px-3 py-1.5 text-xs hover:bg-accent">Cancel</button>
      <button className="rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground hover:opacity-90">
        Save changes
      </button>
    </div>
  );
}
