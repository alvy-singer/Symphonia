"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { useRouter } from "next/navigation";
import {
  Activity,
  FileText,
  Folder,
  GitBranch,
  KanbanSquare,
  Layers,
  LayoutGrid,
  List as ListIcon,
  Plus,
  ScrollText,
  Search,
  ShieldCheck,
  Sparkles,
} from "lucide-react";
import type { RepositorySummary } from "@/lib/repository-model";
import { useDocs, type DocCategory, type DocPage } from "@/lib/docs-store";
import { cn } from "@/lib/utils";

interface PaletteCtx {
  open: () => void;
  /** Optional repo to scope results when palette is opened. */
  setRepoScope: (repoKey: string | undefined) => void;
}

const Ctx = createContext<PaletteCtx>({ open: () => {}, setRepoScope: () => {} });
export const useCommandPalette = () => useContext(Ctx);

interface Command {
  id: string;
  label: string;
  hint?: string;
  group: "Navigate" | "Create" | "Action";
  icon: React.ReactNode;
  run: () => void;
  /** Optional keywords to widen search matching. */
  keywords?: string;
}

interface ProviderProps {
  children: ReactNode;
  /**
   * Hooks injected by the repository layout so the palette can drive in-app
   * actions (open Clarise, switch view mode, start a draft).
   */
  onAskClarise?: () => void;
  onSwitchView?: (mode: "board" | "list") => void;
  onNewDraft?: (repoKey: string, category: DocCategory) => void;
  onNewTask?: (repoKey: string) => void;
  defaultRepoKey?: string;
}

export function CommandPaletteProvider({
  children,
  onAskClarise,
  onSwitchView,
  onNewDraft,
  onNewTask,
  defaultRepoKey,
}: ProviderProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const [repoScope, setRepoScope] = useState<string | undefined>();
  const [repositories, setRepositories] = useState<RepositorySummary[]>([]);
  const inputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const router = useRouter();
  const { pages } = useDocs();

  const open = useCallback(() => setIsOpen(true), []);

  // Cmd/Ctrl+K to open globally.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setIsOpen((v) => !v);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  useEffect(() => {
    if (isOpen) {
      setQuery("");
      setActive(0);
      requestAnimationFrame(() => inputRef.current?.focus());
    }
  }, [isOpen]);

  useEffect(() => {
    let cancelled = false;
    fetch("/api/repositories", { cache: "no-store" })
      .then((res) => (res.ok ? res.json() : Promise.reject(new Error("Could not load repositories"))))
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

  const close = useCallback(() => setIsOpen(false), []);
  const runAndClose = useCallback(
    (fn: () => void) => {
      fn();
      close();
    },
    [close],
  );

  const commands = useMemo<Command[]>(() => {
    const cmds: Command[] = [];
    const slug = (k: string) => k.toLowerCase();

    // Repository navigation
    repositories.forEach((r) => {
      cmds.push({
        id: `repo-${r.key}`,
        label: r.name,
        hint: "Open repository",
        group: "Navigate",
        icon: <Folder className="h-3.5 w-3.5" />,
        run: () => router.push(`/r/${slug(r.key)}/tasks`),
        keywords: r.key,
      });
    });

    const repoForActions = repoScope ?? defaultRepoKey ?? repositories[0]?.key;

    if (repoForActions) {
      const s = slug(repoForActions);
      cmds.push(
        {
          id: "nav-tasks",
          label: "Tasks (Overview)",
          hint: repoForActions,
          group: "Navigate",
          icon: <Layers className="h-3.5 w-3.5" />,
          run: () => router.push(`/r/${s}/tasks`),
          keywords: "overview board list",
        },
        {
          id: "nav-projects",
          label: "Projects",
          hint: repoForActions,
          group: "Navigate",
          icon: <KanbanSquare className="h-3.5 w-3.5" />,
          run: () => router.push(`/r/${s}/projects`),
        },
        {
          id: "nav-docs",
          label: "Docs",
          hint: repoForActions,
          group: "Navigate",
          icon: <FileText className="h-3.5 w-3.5" />,
          run: () => router.push(`/r/${s}/docs`),
        },
        {
          id: "nav-decisions",
          label: "Decisions",
          hint: repoForActions,
          group: "Navigate",
          icon: <ShieldCheck className="h-3.5 w-3.5" />,
          run: () => router.push(`/r/${s}/decisions`),
        },
        {
          id: "nav-reviews",
          label: "Reviews",
          hint: repoForActions,
          group: "Navigate",
          icon: <ScrollText className="h-3.5 w-3.5" />,
          run: () => router.push(`/r/${s}/reviews`),
        },
        {
          id: "nav-runs",
          label: "Run Summaries",
          hint: repoForActions,
          group: "Navigate",
          icon: <Activity className="h-3.5 w-3.5" />,
          run: () => router.push(`/r/${s}/run-summaries`),
        },
        {
          id: "nav-workflow",
          label: "Open WORKFLOW.md",
          hint: "Repository root",
          group: "Navigate",
          icon: <GitBranch className="h-3.5 w-3.5" />,
          run: () => router.push(`/r/${s}/workflow`),
          keywords: "workflow",
        },
        {
          id: "create-task",
          label: "New Task",
          hint: "Create Markdown task",
          group: "Create",
          icon: <Plus className="h-3.5 w-3.5" />,
          run: () => onNewTask?.(repoForActions),
        },
        {
          id: "create-project",
          label: "New Project",
          hint: "Opens an editable draft",
          group: "Create",
          icon: <Plus className="h-3.5 w-3.5" />,
          run: () => onNewDraft?.(repoForActions, "project"),
        },
        {
          id: "create-doc",
          label: "New Doc",
          hint: "Opens an editable draft",
          group: "Create",
          icon: <Plus className="h-3.5 w-3.5" />,
          run: () => onNewDraft?.(repoForActions, "doc"),
        },
        {
          id: "create-decision",
          label: "New Decision",
          hint: "Opens an editable draft",
          group: "Create",
          icon: <Plus className="h-3.5 w-3.5" />,
          run: () => onNewDraft?.(repoForActions, "decision"),
        },
        {
          id: "create-review",
          label: "New Review",
          hint: "Opens an editable draft",
          group: "Create",
          icon: <Plus className="h-3.5 w-3.5" />,
          run: () => onNewDraft?.(repoForActions, "review"),
        },
        {
          id: "create-run",
          label: "New Run Summary",
          hint: "Opens an editable draft",
          group: "Create",
          icon: <Plus className="h-3.5 w-3.5" />,
          run: () => onNewDraft?.(repoForActions, "run-summary"),
        },
        {
          id: "action-clarise",
          label: "Ask Clarise",
          hint: "Workspace assistant",
          group: "Action",
          icon: <Sparkles className="h-3.5 w-3.5 text-violet-500" />,
          run: () => onAskClarise?.(),
        },
        {
          id: "action-board",
          label: "Switch to Board",
          hint: "Tasks view mode",
          group: "Action",
          icon: <LayoutGrid className="h-3.5 w-3.5" />,
          run: () => {
            onSwitchView?.("board");
            router.push(`/r/${s}/tasks`);
          },
        },
        {
          id: "action-list",
          label: "Switch to List",
          hint: "Tasks view mode",
          group: "Action",
          icon: <ListIcon className="h-3.5 w-3.5" />,
          run: () => {
            onSwitchView?.("list");
            router.push(`/r/${s}/tasks`);
          },
        },
      );
    }

    // Document pages — searchable.
    pages.forEach((p) => {
      cmds.push({
        id: `page-${p.id}`,
        label: p.title || "Untitled",
        hint: p.path,
        group: "Navigate",
        icon: <span aria-hidden>{p.icon ?? "·"}</span>,
        run: () => router.push(pageHref(p)),
        keywords: `${p.repo} ${p.category}`,
      });
    });

    return cmds;
  }, [
    pages,
    repoScope,
    repositories,
    router,
    onAskClarise,
    onSwitchView,
    onNewDraft,
    onNewTask,
    defaultRepoKey,
  ]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return commands;
    return commands.filter((c) => {
      const hay = `${c.label} ${c.hint ?? ""} ${c.keywords ?? ""}`.toLowerCase();
      return q.split(/\s+/).every((tok) => hay.includes(tok));
    });
  }, [commands, query]);

  // Reset active index whenever filter changes.
  useEffect(() => {
    setActive(0);
  }, [query]);

  // Group results for display.
  const groups = useMemo(() => {
    const g: Record<string, Command[]> = {};
    for (const c of filtered) {
      g[c.group] = g[c.group] ?? [];
      g[c.group].push(c);
    }
    return Object.entries(g) as [string, Command[]][];
  }, [filtered]);

  const ordered = filtered;

  const onKeyDown: React.KeyboardEventHandler<HTMLInputElement> = (e) => {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setActive((i) => Math.min(i + 1, ordered.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActive((i) => Math.max(i - 1, 0));
    } else if (e.key === "Enter") {
      e.preventDefault();
      const cmd = ordered[active];
      if (cmd) runAndClose(cmd.run);
    } else if (e.key === "Escape") {
      e.preventDefault();
      close();
    }
  };

  // Scroll active item into view.
  useEffect(() => {
    if (!isOpen) return;
    const el = listRef.current?.querySelector<HTMLElement>(`[data-cmd-active="true"]`);
    el?.scrollIntoView({ block: "nearest" });
  }, [active, isOpen]);

  return (
    <Ctx.Provider value={{ open, setRepoScope }}>
      {children}

      {isOpen && (
        <div
          role="dialog"
          aria-label="Command palette"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-start justify-center bg-black/40 p-4 pt-[15svh]"
          onClick={(e) => {
            if (e.target === e.currentTarget) close();
          }}
        >
          <div className="w-full max-w-xl overflow-hidden rounded-xl border bg-popover text-popover-foreground shadow-2xl">
            <div className="flex items-center gap-2 border-b px-3 py-2.5">
              <Search className="h-4 w-4 text-muted-foreground" />
              <input
                ref={inputRef}
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                onKeyDown={onKeyDown}
                placeholder="Search repositories, pages, or actions…"
                aria-label="Command palette search"
                className="flex-1 bg-transparent text-sm outline-none placeholder:text-muted-foreground/70"
              />
              <kbd className="hidden sm:inline-flex items-center rounded border px-1.5 py-0.5 text-[10px] text-muted-foreground">
                Esc
              </kbd>
            </div>
            <div ref={listRef} className="max-h-[60svh] overflow-y-auto">
              {ordered.length === 0 ? (
                <div className="px-4 py-8 text-center text-xs text-muted-foreground">
                  No matches. Try a different word, or press Esc to close.
                </div>
              ) : (
                groups.map(([group, items]) => (
                  <div key={group}>
                    <div className="sticky top-0 bg-popover px-3 pt-2 pb-1 text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
                      {group}
                    </div>
                    <ul>
                      {items.map((cmd) => {
                        const idx = ordered.indexOf(cmd);
                        const isActive = idx === active;
                        return (
                          <li key={cmd.id}>
                            <button
                              data-cmd-active={isActive ? "true" : "false"}
                              onMouseEnter={() => setActive(idx)}
                              onClick={() => runAndClose(cmd.run)}
                              className={cn(
                                "flex w-full items-center gap-2 px-3 py-2 text-left text-sm",
                                isActive
                                  ? "bg-accent text-accent-foreground"
                                  : "text-foreground hover:bg-accent/60",
                              )}
                            >
                              <span className="grid h-5 w-5 place-items-center text-muted-foreground">
                                {cmd.icon}
                              </span>
                              <span className="flex-1 truncate">{cmd.label}</span>
                              {cmd.hint && (
                                <span className="text-[11px] text-muted-foreground truncate max-w-[40%]">
                                  {cmd.hint}
                                </span>
                              )}
                            </button>
                          </li>
                        );
                      })}
                    </ul>
                  </div>
                ))
              )}
            </div>
            <div className="flex items-center justify-between border-t px-3 py-1.5 text-[10px] text-muted-foreground">
              <span>
                <kbd className="rounded border px-1">↑</kbd>{" "}
                <kbd className="rounded border px-1">↓</kbd> navigate
              </span>
              <span>
                <kbd className="rounded border px-1">Enter</kbd> open
              </span>
              <span>
                <kbd className="rounded border px-1">⌘K</kbd> toggle
              </span>
            </div>
          </div>
        </div>
      )}
    </Ctx.Provider>
  );
}

function pageHref(p: DocPage): string {
  const slug = p.repo.toLowerCase();
  switch (p.category) {
    case "task":
      return `/r/${slug}/tasks/${p.id}`;
    case "project":
      return `/r/${slug}/projects/${p.id}`;
    case "doc":
      return `/r/${slug}/docs/${p.id}`;
    case "decision":
      return `/r/${slug}/decisions/${p.id}`;
    case "review":
      return `/r/${slug}/reviews/${p.id}`;
    case "run-summary":
      return `/r/${slug}/run-summaries/${p.id}`;
    case "workflow":
      return `/r/${slug}/workflow`;
  }
}
