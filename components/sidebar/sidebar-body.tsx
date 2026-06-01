"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  ChevronDown,
  FileText,
  Hash,
  KanbanSquare,
  MessageCircle,
  Plus,
  Search,
  Sparkles,
  Users,
  ArrowLeft,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { DocTree } from "@/components/sidebar/doc-tree";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { useCommandPalette } from "@/components/command-palette";
import { useNewTask } from "@/components/new-task-dialog";
import type {
  RepositorySummary,
  SpecArtifact,
  SpecArtifactType,
} from "@/lib/repository-model";

interface Props {
  repoKey: string;
  /** Called after navigating to a destination — used to close the mobile drawer. */
  onNavigate?: () => void;
}

const WORKSPACE_DOCUMENT_CREATE_TYPES: SpecArtifactType[] = [
  "milestone",
  "plan",
  "decision",
];

const WORKSPACE_DOCUMENT_LABELS: Record<SpecArtifactType, string> = {
  codebase_map: "Codebase map",
  codebase_conventions: "Conventions",
  codebase_architecture: "Architecture",
  milestone: "Milestone",
  discussion: "Discussion",
  requirements: "Requirement",
  plan: "Plan",
  task_proposal: "Task proposal",
  task_brief: "Task brief",
  decision: "Decision",
  run_summary: "Run summary",
};

/**
 * Inner sidebar navigation, shared by the desktop sidebar and the mobile drawer.
 * Renders the repository switcher, quick search, primary nav, document tree, and
 * the list of connected repositories.
 */
export function SidebarBody({ repoKey, onNavigate }: Props) {
  const pathname = usePathname();
  const router = useRouter();
  const repoSlug = repoKey.toLowerCase();
  const base = `/r/${repoSlug}`;
  const [repositories, setRepositories] = useState<RepositorySummary[]>([]);
  const [workspaceDocsInitialized, setWorkspaceDocsInitialized] = useState(false);
  const [workspaceDocPending, setWorkspaceDocPending] = useState<SpecArtifactType | null>(null);
  const [workspaceDocError, setWorkspaceDocError] = useState<string | null>(null);
  const palette = useCommandPalette();
  const newTask = useNewTask();
  const repo = useMemo(
    () => repositories.find((r) => r.key.toLowerCase() === repoSlug),
    [repositories, repoSlug],
  );

  useEffect(() => {
    let cancelled = false;
    fetch("/api/repositories", { cache: "no-store" })
      .then((res) =>
        res.ok ? res.json() : Promise.reject(new Error("Could not load repositories")),
      )
      .then((payload: { repositories: RepositorySummary[] }) => {
        if (!cancelled) setRepositories(payload.repositories ?? []);
      })
      .catch(() => {
        if (!cancelled) setRepositories([]);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const loadWorkspaceDocumentState = useCallback(async () => {
    const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/private-workspace`, {
      cache: "no-store",
    });
    const payload = (await res.json()) as {
      privateWorkspace?: { state?: { initialized?: boolean } };
    };
    return Boolean(res.ok && payload.privateWorkspace?.state?.initialized);
  }, [repoKey]);

  useEffect(() => {
    let cancelled = false;
    loadWorkspaceDocumentState()
      .then((initialized) => {
        if (!cancelled) setWorkspaceDocsInitialized(initialized);
      })
      .catch(() => {
        if (!cancelled) setWorkspaceDocsInitialized(false);
      });

    const handler = (event: Event) => {
      const detail = (event as CustomEvent<{ repoKey: string }>).detail;
      if (detail?.repoKey === repoKey) {
        void loadWorkspaceDocumentState().then(setWorkspaceDocsInitialized).catch(() => {
          setWorkspaceDocsInitialized(false);
        });
      }
    };
    window.addEventListener("symphonia:specWorkspaceChanged", handler as EventListener);

    return () => {
      cancelled = true;
      window.removeEventListener("symphonia:specWorkspaceChanged", handler as EventListener);
    };
  }, [loadWorkspaceDocumentState, repoKey]);

  const isActive = (to: string) => pathname === to || pathname.startsWith(to + "/");
  const handleNav = () => onNavigate?.();

  const createWorkspaceDocument = async (type: SpecArtifactType) => {
    setWorkspaceDocPending(type);
    setWorkspaceDocError(null);
    try {
      const res = await fetch(
        `/api/repositories/${encodeURIComponent(repoKey)}/private-workspace/artifacts/${encodeURIComponent(
          type,
        )}`,
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ title: "Untitled", body: "" }),
        },
      );
      const payload = (await res.json()) as { artifact?: SpecArtifact; error?: string };
      if (!res.ok || !payload.artifact) {
        throw new Error(payload.error ?? "Could not create workspace document");
      }
      window.dispatchEvent(new CustomEvent("symphonia:specWorkspaceChanged", { detail: { repoKey } }));
      router.push(specArtifactHref(repoSlug, payload.artifact));
      handleNav();
    } catch (err) {
      setWorkspaceDocError(err instanceof Error ? err.message : "Could not create workspace document");
    } finally {
      setWorkspaceDocPending(null);
    }
  };

  const [showHint, setShowHint] = useState(false);
  useEffect(() => {
    try {
      if (!window.localStorage.getItem("symphonia.kbdHintDismissed")) {
        setShowHint(true);
      }
    } catch {
      /* ignore */
    }
  }, []);
  const dismissHint = () => {
    setShowHint(false);
    try {
      window.localStorage.setItem("symphonia.kbdHintDismissed", "1");
    } catch {
      /* ignore */
    }
  };

  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center justify-between gap-2 border-b px-3 py-2.5">
        <Link
          href="/" onClick={handleNav} title="Return to all repositories"
          className="flex min-w-0 items-center gap-2 rounded-[8px] px-1.5 py-1 transition-colors hover:bg-sidebar-accent"
        >
          <span className="grid h-6 w-6 shrink-0 place-items-center rounded-md bg-foreground text-xs font-bold text-background">
            S
          </span>
          <span className="truncate text-[13px] font-medium tracking-[-0.01em]">{repo?.name ?? "Symphonía"}</span>
          <ChevronDown className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
        </Link>
        <div className="flex items-center gap-0.5">
          <button
            onClick={() => palette.open()}
            aria-label="Search and run commands (Cmd+K)"
            title="Search and run commands (⌘K)"
            className="grid h-7 w-7 place-items-center rounded-[8px] hover:bg-sidebar-accent"
          >
            <Search className="h-3.5 w-3.5" />
          </button>
          <button
            onClick={() => {
              newTask.open();
              handleNav();
            }}
            aria-label="New task"
            title="New task"
            className="grid h-7 w-7 place-items-center rounded-[8px] hover:bg-sidebar-accent"
          >
            <Plus className="h-3.5 w-3.5" />
          </button>
        </div>
      </div>

      <div className="flex-1 space-y-3 overflow-y-auto px-2 py-2">
        <Link
          href="/" onClick={handleNav} title="Return to all repositories"
          className="flex items-center gap-2 rounded-[8px] px-2 py-1 text-[11px] text-muted-foreground transition-colors hover:bg-sidebar-accent hover:text-foreground"
        >
          <ArrowLeft className="h-3 w-3" />
          All repositories
        </Link>

        <button
          onClick={() => palette.open()}
          className="flex w-full items-center gap-2 rounded-[8px] border bg-background/40 px-2 py-1 text-[11px] text-muted-foreground hover:text-foreground"
          aria-label="Open command palette"
        >
          <Search className="h-3 w-3" />
          <span className="flex-1 text-left">Quick search…</span>
          <kbd className="rounded border px-1 text-[9px]">⌘K</kbd>
        </button>

        {showHint && (
          <div className="rounded-md border border-emerald-500/30 bg-emerald-500/5 p-2 text-[11px] text-emerald-700 dark:text-emerald-300">
            <p className="leading-snug">
              Tip: press <kbd className="rounded border px-1 text-[9px]">⌘K</kbd> from anywhere to
              search and run commands.
            </p>
            <button
              type="button"
              onClick={dismissHint}
              className="mt-1 text-[10px] uppercase tracking-wider text-emerald-700/80 hover:text-emerald-700 dark:text-emerald-300/80 dark:hover:text-emerald-300"
            >
              Got it
            </button>
          </div>
        )}

        <nav className="space-y-0.5">
          <NavLink
            to={`${base}/tasks`}
            label="Tasks"
            icon={<KanbanSquare className="h-3.5 w-3.5" />}
            active={pathname === `${base}/tasks`}
            onNavigate={handleNav}
            title="Plan and track work on the board or list view"
          />
          <NavLink
            to={base}
            label="Clarise"
            icon={<Sparkles className="h-3.5 w-3.5" />}
            active={pathname === base}
            onNavigate={handleNav}
            title="Start with the Clarise repo chat"
          />
        </nav>

        <div>
          <div className="mb-1 flex items-center justify-between gap-2 px-1.5">
            <span className="text-[11px] font-semibold uppercase tracking-[0.08em] text-muted-foreground">
              Workspace
            </span>
            {workspaceDocsInitialized && (
              <WorkspaceDocumentCreateMenu
                pending={workspaceDocPending}
                error={workspaceDocError}
                onCreate={createWorkspaceDocument}
              />
            )}
          </div>
          <DocTree repoKey={repoKey} onNavigate={handleNav} />
        </div>

        <div>
          <div className="mb-1 px-1.5 text-[11px] font-semibold uppercase tracking-[0.08em] text-muted-foreground">
            Team
          </div>
          <nav className="space-y-0.5">
            <NavLink
              to={`${base}/team/group-chat`}
              label="Group chat"
              icon={<MessageCircle className="h-3.5 w-3.5" />}
              active={isActive(`${base}/team/group-chat`)}
              onNavigate={handleNav}
              title="Simulated team group chat"
            />
            <NavLink
              to={`${base}/members`}
              label="Members"
              icon={<Users className="h-3.5 w-3.5" />}
              active={isActive(`${base}/members`)}
              onNavigate={handleNav}
              title="People with access to this repository"
            />
          </nav>
        </div>

        <div>
          <div className="mb-1 flex items-center justify-between px-2">
            <span className="text-[11px] font-semibold uppercase tracking-[0.08em] text-muted-foreground">
              Repositories
            </span>
            <Link
              href="/?connect=github"
              onClick={handleNav}
              className="grid h-5 w-5 place-items-center rounded hover:bg-sidebar-accent"
              aria-label="Connect to GitHub"
              title="Connect to GitHub"
            >
              <Plus className="h-3 w-3 text-muted-foreground" />
            </Link>
          </div>
          <div className="space-y-0.5">
            {repositories.map((t) => {
              const active = t.key.toLowerCase() === repoSlug;
              const color = colorForRepo(t.key);
              return (
                <Link
                  key={t.key}
                  href={`/r/${t.key.toLowerCase()}`}
                  onClick={handleNav}
                  title={`Open ${t.name}`}
                  className={cn(
                    "flex w-full items-center gap-2 rounded-[8px] px-2 py-1 text-[13px] transition-colors",
                    active
                      ? "bg-sidebar-accent text-sidebar-accent-foreground"
                      : "text-muted-foreground hover:bg-sidebar-accent hover:text-foreground",
                  )}
                >
                  <span
                    className={cn(
                      "grid h-5 w-5 place-items-center rounded bg-muted text-[10px] font-bold",
                      color,
                    )}
                  >
                    {t.key[0]}
                  </span>
                  <span className="flex-1 truncate text-left">{shortRepoName(t.name)}</span>
                  <Hash className="h-3 w-3 text-muted-foreground" />
                </Link>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}

function WorkspaceDocumentCreateMenu({
  pending,
  error,
  onCreate,
}: {
  pending: SpecArtifactType | null;
  error: string | null;
  onCreate: (type: SpecArtifactType) => Promise<void>;
}) {
  return (
    <Popover>
      <PopoverTrigger asChild>
        <button
          type="button"
          id="workspace-create-document-button"
          aria-label="New workspace document"
          title="New workspace document"
          className="grid h-6 w-6 shrink-0 place-items-center rounded-[8px] text-muted-foreground transition-colors hover:bg-sidebar-accent hover:text-foreground"
        >
          <Plus className="h-3.5 w-3.5" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-52 p-1">
        {WORKSPACE_DOCUMENT_CREATE_TYPES.map((type) => (
          <button
            key={type}
            type="button"
            onClick={() => void onCreate(type)}
            disabled={pending === type}
            className="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-[12px] text-muted-foreground transition-colors hover:bg-accent hover:text-foreground disabled:cursor-not-allowed disabled:opacity-50"
          >
            <FileText className="h-3.5 w-3.5" />
            New {WORKSPACE_DOCUMENT_LABELS[type]}
          </button>
        ))}
        {error && (
          <p className="mt-1 rounded-md border border-amber-500/30 bg-amber-500/10 px-2 py-1 text-[11px] text-amber-700 dark:text-amber-300">
            {error}
          </p>
        )}
      </PopoverContent>
    </Popover>
  );
}

function shortRepoName(name: string): string {
  return name.includes("/") ? name.split("/").at(-1) || name : name;
}

function specArtifactHref(
  slug: string,
  artifact: Pick<SpecArtifact, "type" | "id">,
) {
  return `/r/${slug}/workspace/${encodeURIComponent(artifact.type)}/${encodeURIComponent(
    artifact.id,
  )}`;
}

function colorForRepo(key: string): string {
  const colors = ["text-rose-500", "text-sky-500", "text-violet-500", "text-emerald-500"];
  return colors[key.charCodeAt(0) % colors.length] ?? colors[0];
}

function NavLink({
  to,
  label,
  icon,
  active,
  onNavigate,
  title,
}: {
  to: string;
  label: string;
  icon: React.ReactNode;
  active: boolean;
  onNavigate?: () => void;
  title?: string;
}) {
  return (
    <Link
      href={to}
      onClick={onNavigate}
      title={title}
      className={cn(
        "flex items-center gap-2 rounded-[8px] px-1.5 py-1 text-[13px] transition-colors",
        active
          ? "bg-sidebar-accent font-medium text-sidebar-accent-foreground"
          : "text-muted-foreground hover:bg-sidebar-accent hover:text-foreground",
      )}
    >
      {icon}
      <span className="flex-1 truncate">{label}</span>
    </Link>
  );
}
