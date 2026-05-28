"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import type { KeyboardEvent } from "react";
import {
  ArrowRight,
  Check,
  ChevronRight,
  ExternalLink,
  FolderGit2,
  Github,
  Search,
  Sparkles,
  Trash2,
} from "lucide-react";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import type {
  GitHubConnectionState,
  GitHubInstalledRepository,
  RepositorySummary,
} from "@/lib/repository-model";
import { cn } from "@/lib/utils";

const cardShadow =
  "shadow-[var(--elevation-card)]";

function requestJson<T>(url: string): Promise<T> {
  if (typeof window !== "undefined" && typeof window.fetch === "function") {
    return window.fetch(url, { cache: "no-store" }).then(async (res) => {
      const payload = (await res.json()) as T & { error?: string };
      if (!res.ok) throw new Error(payload.error ?? `Request failed: ${url}`);
      return payload;
    });
  }

  return new Promise<T>((resolve, reject) => {
    if (typeof XMLHttpRequest === "undefined") {
      reject(new Error("Browser request API is unavailable."));
      return;
    }

    const xhr = new XMLHttpRequest();
    xhr.open("GET", url);
    xhr.setRequestHeader("cache-control", "no-store");
    xhr.onload = () => {
      try {
        const payload = JSON.parse(xhr.responseText || "{}") as T & { error?: string };
        if (xhr.status < 200 || xhr.status >= 300) {
          reject(new Error(payload.error ?? `Request failed: ${url}`));
          return;
        }
        resolve(payload);
      } catch (err) {
        reject(err);
      }
    };
    xhr.onerror = () => reject(new Error(`Request failed: ${url}`));
    xhr.send();
  });
}

export default function DashboardPage() {
  const router = useRouter();
  const [repositories, setRepositories] = useState<RepositorySummary[]>([]);
  const [githubRepositories, setGitHubRepositories] = useState<GitHubInstalledRepository[]>([]);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [githubConnection, setGitHubConnection] = useState<GitHubConnectionState | null>(null);
  const [removingKey, setRemovingKey] = useState<string | null>(null);
  const [openingGitHubRepo, setOpeningGitHubRepo] = useState<string | null>(null);
  const [pendingRemoval, setPendingRemoval] = useState<RepositorySummary | null>(null);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    if (params.get("github") === "installed") {
      setNotice("GitHub connected. Pick a repository to open Clarise and create workspace files.");
      window.history.replaceState({}, "", window.location.pathname);
    } else if (params.get("github") === "install-canceled") {
      setError("GitHub installation was canceled.");
      window.history.replaceState({}, "", window.location.pathname);
    }
  }, []);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);

    async function loadDashboard() {
      try {
        const [repoPayload, connectionPayload, githubRepoPayload] = await Promise.all([
          requestJson<{
            repositories?: RepositorySummary[];
            error?: string;
          }>("/api/repositories"),
          requestJson<{
            connection?: GitHubConnectionState;
            error?: string;
          }>("/api/github/connection").catch(() => null),
          requestJson<{
            repositories?: GitHubInstalledRepository[];
            error?: string;
          }>("/api/github/repositories").catch(() => ({ repositories: [] })),
        ]);

        if (!cancelled) {
          setRepositories(repoPayload.repositories ?? []);
          setGitHubConnection(connectionPayload?.connection ?? null);
          setGitHubRepositories(githubRepoPayload.repositories ?? []);
          setError(null);
        }
      } catch (err) {
        if (!cancelled) setError(err instanceof Error ? err.message : "Could not load repositories");
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    void loadDashboard();

    return () => {
      cancelled = true;
    };
  }, []);

  const localGitHubNames = useMemo(() => {
    return new Set(
      repositories
        .map((repo) => {
          if (!repo.github?.owner || !repo.github?.name) return null;
          return `${repo.github.owner}/${repo.github.name}`.toLowerCase();
        })
        .filter((value): value is string => Boolean(value)),
    );
  }, [repositories]);

  const githubOnlyRepositories = useMemo(() => {
    return githubRepositories.filter((repo) => {
      const fullName = (repo.fullName || `${repo.owner}/${repo.name}`).toLowerCase();
      return !localGitHubNames.has(fullName);
    });
  }, [githubRepositories, localGitHubNames]);

  const filteredLocalRepositories = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return repositories;
    return repositories.filter((repo) =>
      `${repo.name} ${repo.key} ${repo.path}`.toLowerCase().includes(q),
    );
  }, [repositories, query]);

  const filteredGitHubRepositories = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return githubOnlyRepositories;
    return githubOnlyRepositories.filter((repo) =>
      `${repo.fullName ?? ""} ${repo.owner} ${repo.name} ${repo.accountLogin ?? ""}`
        .toLowerCase()
        .includes(q),
    );
  }, [githubOnlyRepositories, query]);

  const connectHref = githubConnection?.installationUrl ?? githubConnection?.manageUrl;
  const connectedCount = repositories.length + githubOnlyRepositories.length;
  const hasVisibleRepositories =
    filteredGitHubRepositories.length > 0 || filteredLocalRepositories.length > 0;
  const showEmptyState = !loading && connectedCount === 0;

  const openGitHubConnection = () => {
    if (!connectHref) {
      setError("GitHub connection is unavailable.");
      return;
    }

    window.location.assign(connectHref);
  };

  const openDashboardClarise = () => {
    const repository = repositories[0];
    if (!repository) {
      setError("Connect a repository first.");
      return;
    }
    router.push(`/r/${repository.key.toLowerCase()}`);
  };

  const confirmRemoval = async () => {
    if (!pendingRemoval) return;
    const repository = pendingRemoval;
    setRemovingKey(repository.key);
    setError(null);

    try {
      const res = await fetch(`/api/repositories/${encodeURIComponent(repository.key)}`, {
        method: "DELETE",
      });
      const payload = (await res.json()) as { error?: string };
      if (!res.ok) throw new Error(payload.error ?? "Could not remove repository");

      setRepositories((current) => current.filter((repo) => repo.key !== repository.key));
      setPendingRemoval(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not remove repository");
    } finally {
      setRemovingKey(null);
    }
  };

  const openGitHubRepository = async (repository: GitHubInstalledRepository) => {
    const fullName = repository.fullName || `${repository.owner}/${repository.name}`;
    setOpeningGitHubRepo(fullName);
    setError(null);

    try {
      const res = await fetch("/api/github/repositories/workspace", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(repository),
      });
      const payload = (await res.json()) as {
        repository?: RepositorySummary;
        error?: string;
      };

      if (!res.ok || !payload.repository) {
        throw new Error(payload.error ?? "Could not open repository");
      }

      const openedRepository = payload.repository;
      setRepositories((current) => {
        const exists = current.some((repo) => repo.key === openedRepository.key);
        return exists ? current : [...current, openedRepository];
      });
      router.push(`/r/${openedRepository.key.toLowerCase()}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not open repository");
    } finally {
      setOpeningGitHubRepo(null);
    }
  };

  return (
    <div className="min-h-svh bg-background text-foreground">
      <header className="sticky top-0 z-20 flex h-[60px] items-center justify-between border-b bg-sidebar px-5 text-[15px] text-muted-foreground">
        <Link href="/" className="font-serif text-[28px] font-black tracking-[-0.06em] text-foreground">
          symphonia*
        </Link>
        <div className="flex items-center gap-3">
          <div className="relative hidden sm:block">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search repositories"
              aria-label="Search repositories"
              className="h-9 w-56 rounded-[8px] border bg-background pl-9 pr-3 text-[14px] text-foreground outline-none transition focus:border-primary focus:ring-2 focus:ring-ring/20"
            />
          </div>
          <button
            onClick={openGitHubConnection}
            disabled={!connectHref}
            title={!connectHref ? "GitHub connection is unavailable" : "Connect repo"}
            className={cn(
              "inline-flex h-9 items-center gap-2 rounded-[8px] bg-primary px-4 text-[15px] font-medium text-primary-foreground shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)] transition hover:bg-primary-hover",
              !connectHref && "cursor-not-allowed opacity-55 hover:bg-primary",
            )}
          >
            <Github className="h-4 w-4" />
            Connect repo
          </button>
          <button
            onClick={openDashboardClarise}
            disabled={repositories.length === 0}
            title={repositories.length === 0 ? "Connect a repository first" : "Ask Clarise"}
            className="inline-grid h-9 w-9 place-items-center rounded-[8px] border bg-card text-muted-foreground transition hover:bg-accent hover:text-foreground disabled:cursor-not-allowed disabled:opacity-45"
            aria-label="Ask Clarise"
          >
            <Sparkles className="h-4 w-4" />
          </button>
        </div>
      </header>

      <main className="mx-auto max-w-[976px] px-5 py-10 md:py-14">
        <section className="relative overflow-hidden rounded-[10px] bg-[var(--warm-bg)] px-6 py-10 text-foreground shadow-[0_18px_60px_rgba(0,0,0,0.28)] md:px-10 md:py-12">
          <div className="absolute left-8 top-8 h-1.5 w-24 rotate-[-3deg] rounded-full bg-brand-accent shadow-[0_0_18px_rgba(248,28,229,0.62)]" />
          <div className="absolute right-12 top-16 hidden rounded-[50%] border-[4px] border-muted-foreground/55 px-6 py-3 text-[28px] font-bold italic tracking-[-0.06em] text-muted-foreground/55 md:block">
            ship
          </div>
          <div className="relative max-w-2xl">
            <p className="text-[13px] font-semibold uppercase tracking-[0.18em] text-muted-foreground">
              Repository dashboard
            </p>
            <h1 className="mt-4 text-balance text-[42px] font-bold leading-[1] tracking-[-0.045em] md:text-[58px]">
              Connect a repo. Clarise creates the workspace files.
            </h1>
            <p className="mt-4 max-w-xl text-[17px] leading-7 text-muted-foreground">
              After a repository opens, use Clarise to create the GSD workspace:
              milestones, requirements, plans, decisions, and task briefs.
            </p>
            <div className="mt-7 flex flex-wrap items-center gap-3">
              <button
                onClick={openGitHubConnection}
                disabled={!connectHref}
                className={cn(
                  "inline-flex h-10 items-center gap-2 rounded-[8px] bg-primary px-4 text-[15px] font-semibold text-primary-foreground transition hover:bg-primary-hover",
                  !connectHref && "cursor-not-allowed opacity-55 hover:bg-primary",
                )}
              >
                Connect to GitHub
                <ArrowRight className="h-4 w-4" />
              </button>
            </div>
          </div>
        </section>

        <div className="mt-8 sm:hidden">
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search repositories"
              aria-label="Search repositories"
              className="h-10 w-full rounded-[8px] border bg-background pl-9 pr-3 text-[14px] text-foreground outline-none transition focus:border-primary focus:ring-2 focus:ring-ring/20"
            />
          </div>
        </div>

        {notice && (
          <div className="mt-6 flex items-center gap-2 rounded-[10px] border border-emerald-500/30 bg-emerald-500/10 px-4 py-3 text-[14px] text-emerald-300">
            <Check className="h-4 w-4" />
            {notice}
          </div>
        )}

        {error && (
          <div className="mt-6 rounded-[10px] border border-amber-500/30 bg-amber-500/10 px-4 py-3 text-[14px] text-amber-300">
            {error}
          </div>
        )}

        <div className="mt-10 flex items-end justify-between gap-4">
          <div>
            <p className="text-[13px] font-semibold uppercase tracking-[0.18em] text-muted-foreground">
              Workspaces
            </p>
            <h2 className="mt-2 text-[34px] font-bold leading-none tracking-[-0.045em] text-foreground">
              Repositories
            </h2>
          </div>
          <span className="rounded-full border bg-card px-3 py-1 text-[13px] font-medium text-muted-foreground">
            {connectedCount} connected
          </span>
        </div>

        {loading ? (
          <div
            className={cn(
              "mt-6 rounded-[10px] border border-dashed bg-card p-10 text-center text-[15px] text-muted-foreground",
              cardShadow,
            )}
          >
            Loading repositories...
          </div>
        ) : !hasVisibleRepositories ? (
          <EmptyRepositoryState connectedCount={connectedCount} onConnect={openGitHubConnection} />
        ) : (
          <div className="mt-6 space-y-8">
            {filteredGitHubRepositories.length > 0 && (
              <section>
                <SectionHeader title="GitHub repositories" count={filteredGitHubRepositories.length} />
                <ul className="mt-3 grid gap-4 sm:grid-cols-2">
                  {filteredGitHubRepositories.map((repo) => (
                    <li key={`${repo.installationId}-${repo.fullName ?? `${repo.owner}/${repo.name}`}`}>
                      <GitHubRepositoryCard
                        repository={repo}
                        manageUrl={githubConnection?.manageUrl}
                        opening={openingGitHubRepo === (repo.fullName || `${repo.owner}/${repo.name}`)}
                        onOpen={openGitHubRepository}
                      />
                    </li>
                  ))}
                </ul>
              </section>
            )}

            {filteredLocalRepositories.length > 0 && (
              <section>
                <SectionHeader title="Local repositories" count={filteredLocalRepositories.length} />
                <ul className="mt-3 grid gap-4 sm:grid-cols-2">
                  {filteredLocalRepositories.map((repo) => (
                    <li key={repo.key}>
                      <RepositoryCard
                        repository={repo}
                        removing={removingKey === repo.key}
                        onRemove={(repository) => setPendingRemoval(repository)}
                      />
                    </li>
                  ))}
                </ul>
              </section>
            )}
          </div>
        )}
      </main>

      <ConfirmDialog
        open={pendingRemoval != null}
        onOpenChange={(open) => {
          if (!open) setPendingRemoval(null);
        }}
        title={pendingRemoval ? `Remove ${pendingRemoval.name}?` : "Remove repository"}
        description={
          <>
            This removes <span className="font-medium text-foreground">{pendingRemoval?.name}</span>{" "}
            from Symphonia. Your GitHub repository and local files won&apos;t be affected.
          </>
        }
        confirmLabel={removingKey ? "Removing..." : "Remove"}
        cancelLabel="Cancel"
        destructive
        pending={removingKey != null}
        onConfirm={confirmRemoval}
      />
    </div>
  );
}

function EmptyRepositoryState({
  connectedCount,
  onConnect,
}: {
  connectedCount: number;
  onConnect: () => void;
}) {
  return (
    <div
      className={cn(
        "mt-6 rounded-[10px] bg-card p-8 text-center md:p-10",
        cardShadow,
      )}
    >
      <div className="mx-auto grid h-14 w-14 place-items-center rounded-[10px] bg-[var(--card-alt)] text-primary">
        <FolderGit2 className="h-7 w-7" />
      </div>
      <h3 className="mt-5 text-[28px] font-bold tracking-[-0.04em] text-foreground">
        {connectedCount > 0 ? "No matching repositories" : "No repositories connected yet"}
      </h3>
      <p className="mx-auto mt-3 max-w-md text-[15px] leading-6 text-muted-foreground">
        Connect GitHub to bring your repositories into Symphonia. Once a repo is opened,
        Clarise becomes the first stop for creating the editable workspace files.
      </p>
      <div className="mt-6 flex flex-wrap items-center justify-center gap-3">
        <button
          onClick={onConnect}
          className="inline-flex h-10 items-center gap-2 rounded-[8px] bg-primary px-4 text-[15px] font-semibold text-primary-foreground transition hover:bg-primary-hover"
        >
          <Github className="h-4 w-4" />
          Connect to GitHub
        </button>
        <button
          disabled
          title="Coming soon - demo repositories are on the way."
          className="inline-flex h-10 cursor-not-allowed items-center gap-2 rounded-[8px] border bg-card px-4 text-[15px] font-medium text-muted-foreground"
        >
          <Sparkles className="h-4 w-4" />
          Demo repository
        </button>
      </div>
    </div>
  );
}

function SectionHeader({ title, count }: { title: string; count: number }) {
  return (
    <div className="flex items-center justify-between">
      <h3 className="text-[17px] font-bold tracking-[-0.025em] text-foreground">{title}</h3>
      <span className="text-[13px] tabular-nums text-muted-foreground">{count}</span>
    </div>
  );
}

function GitHubRepositoryCard({
  repository,
  manageUrl,
  opening,
  onOpen,
}: {
  repository: GitHubInstalledRepository;
  manageUrl?: string;
  opening: boolean;
  onOpen: (repository: GitHubInstalledRepository) => void;
}) {
  const fullName = repository.fullName || `${repository.owner}/${repository.name}`;
  const openWorkspace = () => {
    if (!opening) onOpen(repository);
  };
  const openFromKeyboard = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    openWorkspace();
  };

  return (
    <div
      role="link"
      tabIndex={0}
      aria-label={`Open ${fullName} repository`}
      aria-busy={opening}
      onClick={openWorkspace}
      onKeyDown={openFromKeyboard}
      className={cn(
        "group cursor-pointer rounded-[10px] bg-card p-5 text-left transition duration-200 hover:-translate-y-0.5 hover:shadow-[var(--elevation-card-hover)] focus:outline-none focus:ring-2 focus:ring-ring/30",
        cardShadow,
        opening && "cursor-wait opacity-75",
      )}
    >
      <div className="flex items-center gap-3">
        <span className="grid h-11 w-11 place-items-center rounded-[9px] bg-[var(--card-alt)] text-primary">
          <Github className="h-5 w-5" />
        </span>
        <div className="min-w-0 flex-1">
          <h4 className="truncate text-[17px] font-bold tracking-[-0.025em] text-foreground">
            {fullName}
          </h4>
          <p className="truncate text-[13px] text-muted-foreground">
            Open in Clarise to create workspace files
            {repository.defaultBranch ? ` / ${repository.defaultBranch}` : ""}
          </p>
        </div>
        <ChevronRight className="h-5 w-5 shrink-0 text-muted-foreground transition-colors group-hover:text-foreground" />
      </div>

      <dl className="mt-5 grid grid-cols-3 gap-2 text-center">
        <Stat label="Repo" value={opening ? "Opening" : "Connected"} />
        <Stat label="Workspace" value="Needs Clarise" muted />
        <Stat label="Account" value={repository.accountLogin ?? repository.owner} />
      </dl>

      <div className="mt-4 flex items-center justify-between gap-2">
        <span className="inline-flex items-center gap-1 text-[13px] font-medium text-primary">
          {opening ? "Opening Clarise..." : "Open Clarise"}
          <ArrowRight className="h-3.5 w-3.5" />
        </span>
        <div className="relative z-10 flex items-center gap-3">
          {repository.url && (
            <a
              href={repository.url}
              target="_blank"
              rel="noreferrer"
              onClick={(event) => event.stopPropagation()}
              onKeyDown={(event) => event.stopPropagation()}
              className="inline-flex items-center gap-1 text-[13px] text-muted-foreground hover:text-foreground"
            >
              GitHub
              <ExternalLink className="h-3.5 w-3.5" />
            </a>
          )}
          {manageUrl && (
            <a
              href={manageUrl}
              onClick={(event) => event.stopPropagation()}
              onKeyDown={(event) => event.stopPropagation()}
              className="inline-flex items-center gap-1 text-[13px] text-muted-foreground hover:text-foreground"
            >
              Repos
              <ExternalLink className="h-3.5 w-3.5" />
            </a>
          )}
        </div>
      </div>
    </div>
  );
}

function RepositoryCard({
  repository,
  removing,
  onRemove,
}: {
  repository: RepositorySummary;
  removing: boolean;
  onRemove: (repository: RepositorySummary) => void;
}) {
  const workspace = repository.workspace;
  const files = workspace?.initialized ? "Ready" : "Missing";
  const rules = workspace?.workflow.exists ? "Ready" : "Missing";
  const href = `/r/${repository.key.toLowerCase()}`;
  const workspaceReady = workspace?.initialized && workspace.workflow.exists;

  return (
    <div
      className={cn(
        "group relative rounded-[10px] bg-card p-5 transition duration-200 hover:-translate-y-0.5 hover:shadow-[var(--elevation-card-hover)]",
        cardShadow,
      )}
    >
      <Link
        href={href}
        aria-label={`Open ${repository.name} repository`}
        className="absolute inset-0 z-10 rounded-[10px] focus:outline-none focus:ring-2 focus:ring-ring/30"
      />
      <div className="flex items-center gap-3">
        <span
          className={cn(
            "grid h-11 w-11 shrink-0 place-items-center rounded-[9px] bg-[var(--card-alt)] text-[15px] font-bold",
            colorForRepo(repository.key),
          )}
        >
          {repository.key[0]}
        </span>
        <div className="min-w-0 flex-1">
          <h4 className="truncate text-[17px] font-bold tracking-[-0.025em] text-foreground">
            {repository.name}
          </h4>
          <p className="truncate text-[13px] text-muted-foreground">
            {repository.github?.owner && repository.github?.name
              ? `${repository.github.owner}/${repository.github.name}`
              : "Local repository"}
          </p>
          <p className="mt-1 truncate text-[12px] text-muted-foreground">
            {workspaceReady
              ? "Workspace files are ready to edit"
              : "Use Clarise to create workspace files"}
          </p>
        </div>
        <ChevronRight className="h-5 w-5 text-muted-foreground transition-colors group-hover:text-foreground" />
      </div>

      <dl className="mt-5 grid grid-cols-3 gap-2 text-center">
        <Stat label="Start" value={workspaceReady ? "Workspace" : "Clarise"} />
        <Stat label="Files" value={files} muted={!workspace?.initialized} />
        <Stat label="Rules" value={rules} muted={!workspace?.workflow.exists} />
      </dl>

      <div className="mt-4 flex items-center justify-between gap-3">
        <span className="inline-flex items-center gap-1 text-[13px] font-medium text-primary">
          {workspaceReady ? "Open repo" : "Open Clarise"}
          <ArrowRight className="h-3.5 w-3.5" />
        </span>
        <button
          type="button"
          onClick={() => onRemove(repository)}
          disabled={removing}
          className="relative z-20 inline-flex h-8 shrink-0 items-center gap-1 rounded-[8px] border px-3 text-[12px] font-medium text-muted-foreground transition hover:border-red-500/30 hover:bg-red-500/10 hover:text-red-300 disabled:cursor-not-allowed disabled:opacity-50"
          aria-label={`Remove ${repository.name} from Symphonia`}
        >
          <Trash2 className="h-3.5 w-3.5" />
          {removing ? "Removing" : "Remove"}
        </button>
      </div>
    </div>
  );
}

function Stat({ label, value, muted }: { label: string; value: string; muted?: boolean }) {
  return (
    <div className="rounded-[8px] bg-[var(--card-alt)] px-2 py-2">
      <dt className="text-[10px] font-semibold uppercase tracking-[0.08em] text-muted-foreground">
        {label}
      </dt>
      <dd className={cn("truncate text-[14px] font-bold tabular-nums text-foreground", muted && "text-amber-300")}>
        {value}
      </dd>
    </div>
  );
}

function colorForRepo(key: string): string {
  const colors = ["text-red-400", "text-primary", "text-violet-400", "text-emerald-400"];
  return colors[key.charCodeAt(0) % colors.length] ?? colors[0];
}
