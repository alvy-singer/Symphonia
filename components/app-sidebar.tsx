"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  ChevronDown,
  Hash,
  Inbox,
  KanbanSquare,
  Moon,
  Plus,
  Search,
  Settings,
  Sun,
  Users,
  ArrowLeft,
} from "lucide-react";
import { repositories } from "@/data/mock";
import { cn } from "@/lib/utils";
import { useTheme } from "@/components/theme-provider";
import { DocTree } from "@/components/sidebar/doc-tree";
import { useCommandPalette } from "@/components/command-palette";
import { useDraftHost } from "@/components/draft-host";

interface Props {
  repoKey: string;
}

/**
 * Repository sidebar, refreshed for the Notion-like document workspace.
 *
 * - Top: repository switcher and quick actions (Search opens Cmd+K, +
 *   creates a new Task draft).
 * - Workspace anchors: Inbox + Repository Overview (Tasks board/list).
 * - Document tree: Tasks, Projects, Docs, Decisions, Reviews, Run Summaries,
 *   plus pinned WORKFLOW.md. Each + opens a draft.
 * - Bottom: Members, Settings, theme toggle.
 */
export function AppSidebar({ repoKey }: Props) {
  const pathname = usePathname();
  const { theme, toggle } = useTheme();
  const repoSlug = repoKey.toLowerCase();
  const base = `/r/${repoSlug}`;
  const repo = repositories.find((r) => r.key.toLowerCase() === repoSlug);
  const palette = useCommandPalette();
  const { startDraft } = useDraftHost();

  const isActive = (to: string) => pathname === to || pathname.startsWith(to + "/");

  return (
    <aside className="hidden lg:flex h-svh w-64 shrink-0 flex-col border-r bg-sidebar text-sidebar-foreground">
      <div className="flex items-center justify-between gap-2 px-3 py-2.5 border-b">
        <Link
          href="/"
          className="flex items-center gap-2 rounded-md px-1.5 py-1 hover:bg-sidebar-accent transition-colors min-w-0"
        >
          <span className="grid h-6 w-6 place-items-center rounded-md bg-foreground text-background text-xs font-bold shrink-0">
            S
          </span>
          <span className="text-sm font-medium truncate">{repo?.name ?? "Symphonia"}</span>
          <ChevronDown className="h-3.5 w-3.5 text-muted-foreground shrink-0" />
        </Link>
        <div className="flex items-center gap-0.5">
          <button
            onClick={() => palette.open()}
            aria-label="Search and run commands (Cmd+K)"
            title="Search and run commands (⌘K)"
            className="grid h-7 w-7 place-items-center rounded-md hover:bg-sidebar-accent"
          >
            <Search className="h-3.5 w-3.5" />
          </button>
          <button
            onClick={() => startDraft(repoKey, "task")}
            aria-label="New task"
            title="New task"
            className="grid h-7 w-7 place-items-center rounded-md hover:bg-sidebar-accent"
          >
            <Plus className="h-3.5 w-3.5" />
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto px-2 py-2 space-y-3">
        <Link
          href="/"
          className="flex items-center gap-2 rounded-md px-2 py-1 text-[11px] text-muted-foreground hover:bg-sidebar-accent hover:text-foreground transition-colors"
        >
          <ArrowLeft className="h-3 w-3" />
          All repositories
        </Link>

        <button
          onClick={() => palette.open()}
          className="w-full flex items-center gap-2 rounded-md border bg-background/40 px-2 py-1 text-[11px] text-muted-foreground hover:text-foreground"
          aria-label="Open command palette"
        >
          <Search className="h-3 w-3" />
          <span className="flex-1 text-left">Quick search…</span>
          <kbd className="rounded border px-1 text-[9px]">⌘K</kbd>
        </button>

        <nav className="space-y-0.5">
          <NavLink
            to={`${base}/inbox`}
            label="Inbox"
            count={3}
            icon={<Inbox className="h-3.5 w-3.5" />}
            active={isActive(`${base}/inbox`)}
          />
          <NavLink
            to={`${base}/tasks`}
            label="Overview"
            icon={<KanbanSquare className="h-3.5 w-3.5" />}
            active={pathname === `${base}/tasks`}
            hint="Board / List"
          />
        </nav>

        <div>
          <div className="mb-1 px-1.5 text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
            Workspace
          </div>
          <DocTree
            repoKey={repoKey}
            onNew={(category) => startDraft(repoKey, category)}
          />
        </div>

        <nav className="space-y-0.5">
          <NavLink
            to={`${base}/members`}
            label="Members"
            icon={<Users className="h-3.5 w-3.5" />}
            active={isActive(`${base}/members`)}
          />
          <NavLink
            to={`${base}/settings`}
            label="Settings"
            icon={<Settings className="h-3.5 w-3.5" />}
            active={isActive(`${base}/settings`)}
          />
        </nav>

        <div>
          <div className="flex items-center justify-between px-2 mb-1">
            <span className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
              Repositories
            </span>
            <Link
              href="/"
              className="grid h-5 w-5 place-items-center rounded hover:bg-sidebar-accent"
              aria-label="Add repository"
            >
              <Plus className="h-3 w-3 text-muted-foreground" />
            </Link>
          </div>
          <div className="space-y-0.5">
            {repositories.map((t) => {
              const active = t.key.toLowerCase() === repoSlug;
              return (
                <Link
                  key={t.id}
                  href={`/r/${t.key.toLowerCase()}/tasks`}
                  className={cn(
                    "w-full flex items-center gap-2 rounded-md px-2 py-1 text-[13px] transition-colors",
                    active
                      ? "bg-sidebar-accent text-sidebar-accent-foreground"
                      : "text-muted-foreground hover:bg-sidebar-accent hover:text-foreground",
                  )}
                >
                  <span
                    className={cn(
                      "grid h-5 w-5 place-items-center rounded text-[10px] font-bold bg-muted",
                      t.color,
                    )}
                  >
                    {t.key[0]}
                  </span>
                  <span className="flex-1 text-left truncate">{t.name.split("/")[1]}</span>
                  <Hash className="h-3 w-3 text-muted-foreground" />
                </Link>
              );
            })}
          </div>
        </div>
      </div>

      <div className="border-t px-3 py-2 flex items-center justify-between gap-2">
        <button className="flex items-center gap-2 rounded-md px-1.5 py-1 hover:bg-sidebar-accent transition-colors">
          <span className="grid h-6 w-6 place-items-center rounded-full bg-rose-500 text-[10px] font-medium text-white">
            AM
          </span>
          <span className="text-sm">Ava Martinez</span>
        </button>
        <button
          onClick={toggle}
          aria-label="Toggle theme"
          title={theme === "dark" ? "Switch to light" : "Switch to dark"}
          className="grid h-7 w-7 place-items-center rounded-md hover:bg-sidebar-accent text-muted-foreground hover:text-foreground"
        >
          {theme === "dark" ? <Sun className="h-3.5 w-3.5" /> : <Moon className="h-3.5 w-3.5" />}
        </button>
      </div>
    </aside>
  );
}

function NavLink({
  to,
  label,
  icon,
  active,
  count,
  hint,
}: {
  to: string;
  label: string;
  icon: React.ReactNode;
  active: boolean;
  count?: number;
  hint?: string;
}) {
  return (
    <Link
      href={to}
      className={cn(
        "flex items-center gap-2 rounded-md px-1.5 py-1 text-[13px] transition-colors",
        active
          ? "bg-sidebar-accent text-sidebar-accent-foreground font-medium"
          : "text-muted-foreground hover:bg-sidebar-accent hover:text-foreground",
      )}
    >
      {icon}
      <span className="flex-1 truncate">{label}</span>
      {count != null && (
        <span className="text-[10px] tabular-nums text-muted-foreground">{count}</span>
      )}
      {hint && (
        <span className="text-[10px] text-muted-foreground/70 truncate max-w-[6rem]">{hint}</span>
      )}
    </Link>
  );
}
