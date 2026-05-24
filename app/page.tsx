"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import {
  Check,
  ChevronRight,
  ExternalLink,
  FolderGit2,
  Github,
  Search,
  Trash2,
} from "lucide-react";
import type {
  GitHubConnectionState,
  GitHubInstalledRepository,
  RepositorySummary,
} from "@/lib/repository-model";
import { cn } from "@/lib/utils";

export default function RepositoriesPage() {
  const [repositories, setRepositories] = useState<RepositorySummary[]>([]);
  const [githubRepositories, setGitHubRepositories] = useState<GitHubInstalledRepository[]>([]);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [githubConnection, setGitHubConnection] = useState<GitHubConnectionState | null>(null);
  const [removingKey, setRemovingKey] = useState<string | null>(null);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    if (params.get("github") === "installed") {
      setNotice("GitHub connected. Allowed repositories are available below.");
      window.history.replaceState({}, "", window.location.pathname);
    } else if (params.get("github") === "install-canceled") {
      setError("GitHub installation was canceled.");
      window.history.replaceState({}, "", window.location.pathname);
    }
  }, []);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);

    Promise.all([
      fetch("/api/repositories", { cache: "no-store" }).then(async (res) => {
        const payload = (await res.json()) as {
          repositories?: RepositorySummary[];
          error?: string;
        };
        if (!res.ok) throw new Error(payload.error ?? "Could not load repositories");
        return payload.repositories ?? [];
      }),
      fetch("/api/github/connection", { cache: "no-store" }).then(async (res) => {
        const payload = (await res.json()) as {
          connection?: GitHubConnectionState;
          error?: string;
        };
        if (!res.ok) return null;
        return payload.connection ?? null;
      }),
      fetch("/api/github/repositories", { cache: "no-store" }).then(async (res) => {
        const payload = (await res.json()) as {
          repositories?: GitHubInstalledRepository[];
          error?: string;
        };
        if (!res.ok) return [];
        return payload.repositories ?? [];
      }),
    ])
      .then(([next, connection, githubRepos]) => {
        if (!cancelled) {
          setRepositories(next);
          setGitHubConnection(connection);
          setGitHubRepositories(githubRepos);
          setError(null);
        }
      })
      .catch((err) => {
        if (!cancelled) setError(err instanceof Error ? err.message : "Could not load repositories");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

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

  const connectHref = githubConnection?.installationUrl;
  const connectedCount = repositories.length + githubOnlyRepositories.length;
  const hasVisibleRepositories =
    filteredGitHubRepositories.length > 0 || filteredLocalRepositories.length > 0;

  const openGitHubConnection = () => {
    if (!connectHref) {
      setError("GitHub connection is unavailable.");
      return;
    }

    window.location.assign(connectHref);
  };

  const removeRepository = async (repository: RepositorySummary) => {
    const confirmed = window.confirm(
      `Remove ${repository.name} from Symphonía? Local files and GitHub access will not be changed.`,
    );
    if (!confirmed) return;

    setRemovingKey(repository.key);
    setError(null);

    try {
      const res = await fetch(`/api/repositories/${encodeURIComponent(repository.key)}`, {
        method: "DELETE",
      });
      const payload = (await res.json()) as { error?: string };
      if (!res.ok) throw new Error(payload.error ?? "Could not remove repository");

      setRepositories((current) => current.filter((repo) => repo.key !== repository.key));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not remove repository");
    } finally {
      setRemovingKey(null);
    }
  };

  return (
    <div className="min-h-svh bg-background text-foreground">
      <header className="sticky top-0 z-10 flex items-center justify-between gap-3 border-b bg-background/95 px-4 py-2.5 backdrop-blur">
        <div className="flex items-center gap-2 text-sm">
          <span className="grid h-6 w-6 place-items-center rounded-md bg-foreground text-[11px] font-bold text-background">
            S
          </span>
          <span className="font-semibold">Symphonía</span>
          <span className="text-muted-foreground">/</span>
          <span className="text-muted-foreground">Repositories</span>
        </div>
        <div className="flex items-center gap-1">
          <div className="relative hidden sm:block">
            <Search className="pointer-events-none absolute left-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground" />
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search repositories"
              className="w-56 rounded-md border bg-background py-1 pl-7 pr-2 text-[12px] focus:outline-none focus:ring-2 focus:ring-ring"
            />
          </div>
          <button
            onClick={openGitHubConnection}
            disabled={!connectHref}
            title={!connectHref ? "GitHub connection is unavailable" : undefined}
            className={cn(
              "inline-flex items-center gap-1.5 rounded-md bg-primary px-2.5 py-1 text-[12px] text-primary-foreground hover:opacity-90",
              !connectHref && "cursor-not-allowed opacity-50 hover:opacity-50",
            )}
          >
            <Github className="h-3.5 w-3.5" />
            Connect to GitHub
          </button>
        </div>
      </header>

      <main className="mx-auto max-w-5xl p-4 sm:p-6">
        <div className="mb-5 flex items-end justify-between gap-4">
          <div>
            <h1 className="text-xl font-semibold tracking-tight">Repositories</h1>
            <p className="mt-1 text-sm text-muted-foreground">
              Choose repositories on GitHub and return here automatically.
            </p>
          </div>
          <span className="text-xs tabular-nums text-muted-foreground">
            {connectedCount} connected
          </span>
        </div>

        {notice && (
          <div className="mb-4 flex items-center gap-2 rounded-md border border-emerald-500/30 bg-emerald-500/10 px-3 py-2 text-sm text-emerald-700 dark:text-emerald-300">
            <Check className="h-4 w-4" />
            {notice}
          </div>
        )}

        {error && (
          <div className="mb-4 rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-sm text-amber-700 dark:text-amber-300">
            {error}
          </div>
        )}

        {loading ? (
          <div className="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
            Loading repositories...
          </div>
        ) : !hasVisibleRepositories ? (
          <div className="rounded-lg border border-dashed p-8 text-center">
            <FolderGit2 className="mx-auto h-8 w-8 text-muted-foreground" />
            <h2 className="mt-3 text-sm font-medium">
              {connectedCount > 0 ? "No matching repositories" : "No repositories connected"}
            </h2>
            <p className="mx-auto mt-1 max-w-sm text-sm text-muted-foreground">
              Connect GitHub, choose repositories, and return here automatically.
            </p>
            <button
              onClick={openGitHubConnection}
              disabled={!connectHref}
              title={!connectHref ? "GitHub connection is unavailable" : undefined}
              className={cn(
                "mt-4 inline-flex items-center gap-1.5 rounded-md bg-primary px-3 py-1.5 text-sm text-primary-foreground hover:opacity-90",
                !connectHref && "cursor-not-allowed opacity-50 hover:opacity-50",
              )}
            >
              <Github className="h-4 w-4" />
              Connect to GitHub
            </button>
          </div>
        ) : (
          <div className="space-y-6">
            {filteredGitHubRepositories.length > 0 && (
              <section>
                <div className="mb-2 flex items-center justify-between">
                  <h2 className="text-sm font-medium">GitHub repositories</h2>
                  <span className="text-xs tabular-nums text-muted-foreground">
                    {filteredGitHubRepositories.length}
                  </span>
                </div>
                <ul className="grid gap-3 sm:grid-cols-2">
                  {filteredGitHubRepositories.map((repo) => (
                    <li key={`${repo.installationId}-${repo.fullName ?? `${repo.owner}/${repo.name}`}`}>
                      <GitHubRepositoryCard repository={repo} manageUrl={githubConnection?.manageUrl} />
                    </li>
                  ))}
                </ul>
              </section>
            )}

            {filteredLocalRepositories.length > 0 && (
              <section>
                <div className="mb-2 flex items-center justify-between">
                  <h2 className="text-sm font-medium">Local workspaces</h2>
                  <span className="text-xs tabular-nums text-muted-foreground">
                    {filteredLocalRepositories.length}
                  </span>
                </div>
                <ul className="grid gap-3 sm:grid-cols-2">
                  {filteredLocalRepositories.map((repo) => (
                    <li key={repo.key}>
                      <RepositoryCard
                        repository={repo}
                        removing={removingKey === repo.key}
                        onRemove={removeRepository}
                      />
                    </li>
                  ))}
                </ul>
              </section>
            )}
          </div>
        )}
      </main>
    </div>
  );
}

function GitHubRepositoryCard({
  repository,
  manageUrl,
}: {
  repository: GitHubInstalledRepository;
  manageUrl?: string;
}) {
  const fullName = repository.fullName || `${repository.owner}/${repository.name}`;

  return (
    <div className="rounded-lg border bg-card p-4 transition-colors hover:border-foreground/20">
      <div className="flex items-center gap-3">
        <span className="grid h-9 w-9 place-items-center rounded-md bg-muted text-emerald-500">
          <Github className="h-4 w-4" />
        </span>
        <div className="min-w-0 flex-1">
          <h3 className="truncate text-sm font-semibold">{fullName}</h3>
          <p className="truncate text-[11px] text-muted-foreground">
            Connected on GitHub
            {repository.defaultBranch ? ` / ${repository.defaultBranch}` : ""}
          </p>
        </div>
        {repository.url && (
          <a
            href={repository.url}
            target="_blank"
            rel="noreferrer"
            className="inline-flex h-8 shrink-0 items-center gap-1 rounded-md border px-2 text-[11px] text-muted-foreground hover:bg-accent hover:text-foreground"
          >
            Open
            <ExternalLink className="h-3.5 w-3.5" />
          </a>
        )}
      </div>

      <dl className="mt-4 grid grid-cols-3 gap-2 text-center">
        <Stat label="Status" value="Connected" />
        <Stat label="Account" value={repository.accountLogin ?? repository.owner} />
        <Stat label="Branch" value={repository.defaultBranch ?? "-"} />
      </dl>

      {manageUrl && (
        <a
          href={manageUrl}
          className="mt-3 inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
        >
          Change selection
          <ExternalLink className="h-3 w-3" />
        </a>
      )}
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
  const folders = workspace?.initialized ? "Present" : "Missing";
  const workflow = workspace?.workflow.exists ? "Present" : "Missing";

  return (
    <div className="rounded-lg border bg-card p-4 transition-colors hover:border-foreground/20">
      <div className="flex items-center gap-3">
        <Link
          href={`/r/${repository.key.toLowerCase()}/tasks`}
          className="group flex min-w-0 flex-1 items-center gap-3 rounded-md focus:outline-none focus:ring-2 focus:ring-ring"
        >
          <span
            className={cn(
              "grid h-9 w-9 place-items-center rounded-md bg-muted text-sm font-bold",
              colorForRepo(repository.key),
            )}
          >
            {repository.key[0]}
          </span>
          <div className="min-w-0 flex-1">
            <h3 className="truncate text-sm font-semibold">{repository.name}</h3>
            <p className="truncate text-[11px] text-muted-foreground">
              {repository.github?.owner && repository.github?.name
                ? `${repository.github.owner}/${repository.github.name}`
                : "Local workspace"}
            </p>
          </div>
          <ChevronRight className="h-4 w-4 text-muted-foreground transition-colors group-hover:text-foreground" />
        </Link>
        <button
          type="button"
          onClick={() => onRemove(repository)}
          disabled={removing}
          className="inline-flex h-8 shrink-0 items-center gap-1 rounded-md border px-2 text-[11px] text-muted-foreground hover:border-destructive/30 hover:bg-destructive/10 hover:text-destructive disabled:cursor-not-allowed disabled:opacity-50"
          aria-label={`Remove ${repository.name} from Symphonía`}
        >
          <Trash2 className="h-3.5 w-3.5" />
          {removing ? "Removing" : "Remove"}
        </button>
      </div>

      <dl className="mt-4 grid grid-cols-3 gap-2 text-center">
        <Stat label="Tasks" value={String(repository.taskCount ?? 0)} />
        <Stat label="Folders" value={folders} muted={!workspace?.initialized} />
        <Stat label="Workflow" value={workflow} muted={!workspace?.workflow.exists} />
      </dl>
    </div>
  );
}

function Stat({ label, value, muted }: { label: string; value: string; muted?: boolean }) {
  return (
    <div className="rounded-md bg-muted/40 px-1 py-2">
      <dt className="text-[10px] uppercase text-muted-foreground">{label}</dt>
      <dd className={cn("truncate text-sm font-semibold tabular-nums", muted && "text-amber-600")}>
        {value}
      </dd>
    </div>
  );
}

function colorForRepo(key: string): string {
  const colors = ["text-rose-500", "text-sky-500", "text-violet-500", "text-emerald-500"];
  return colors[key.charCodeAt(0) % colors.length] ?? colors[0];
}
