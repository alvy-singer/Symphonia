"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { Menu, Moon, Sun, X } from "lucide-react";
import { cn } from "@/lib/utils";
import { useTheme } from "@/components/theme-provider";
import { SidebarBody } from "@/components/sidebar/sidebar-body";
import type { RepositorySummary } from "@/lib/repository-model";

interface Props {
  repoKey: string;
}

/**
 * Repository sidebar.
 *
 * - On `lg+` viewports, renders a fixed sidebar to the left of the content.
 * - Below `lg`, renders a sticky top bar (with logo, repo name, theme toggle,
 *   and a hamburger button) plus a slide-over drawer that contains the same
 *   navigation as the desktop sidebar.
 *
 * The footer (avatar + theme toggle) is rendered at the bottom of both the
 * desktop sidebar and the mobile drawer for consistency.
 */
export function AppSidebar({ repoKey }: Props) {
  const { theme, toggle } = useTheme();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [repo, setRepo] = useState<RepositorySummary | null>(null);
  const pathname = usePathname();
  const repoSlug = repoKey.toLowerCase();

  // Lightweight fetch for the top-bar repo name. SidebarBody fetches the full list.
  useEffect(() => {
    let cancelled = false;
    fetch("/api/repositories", { cache: "no-store" })
      .then((res) => (res.ok ? res.json() : null))
      .then((payload: { repositories: RepositorySummary[] } | null) => {
        if (cancelled || !payload) return;
        const match = payload.repositories.find((r) => r.key.toLowerCase() === repoSlug);
        setRepo(match ?? null);
      })
      .catch(() => {
        /* ignore */
      });
    return () => {
      cancelled = true;
    };
  }, [repoSlug]);

  // Close drawer on navigation.
  useEffect(() => {
    setMobileOpen(false);
  }, [pathname]);

  // Lock body scroll while drawer is open.
  useEffect(() => {
    if (!mobileOpen) return;
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = previous;
    };
  }, [mobileOpen]);

  // Close drawer on Escape.
  useEffect(() => {
    if (!mobileOpen) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setMobileOpen(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [mobileOpen]);

  const repoName = useMemo(() => repo?.name ?? "Symphonía", [repo]);

  return (
    <>
      {/* Mobile sticky top bar */}
      <header className="sticky top-0 z-30 flex items-center justify-between gap-2 border-b bg-background/95 px-3 py-2 backdrop-blur lg:hidden">
        <div className="flex min-w-0 items-center gap-2">
          <button
            type="button"
            onClick={() => setMobileOpen(true)}
            aria-label="Open navigation"
            aria-expanded={mobileOpen}
            className="grid h-8 w-8 place-items-center rounded-md border hover:bg-accent"
          >
            <Menu className="h-4 w-4" />
          </button>
          <Link
            href="/"
            className="flex min-w-0 items-center gap-2 rounded-md px-1 py-0.5 hover:bg-accent"
            aria-label="Go to all repositories"
          >
            <span className="grid h-6 w-6 shrink-0 place-items-center rounded-md bg-foreground text-xs font-bold text-background">
              S
            </span>
            <span className="truncate text-sm font-medium">{repoName}</span>
          </Link>
        </div>
        <button
          type="button"
          onClick={toggle}
          aria-label="Toggle theme"
          title={theme === "dark" ? "Switch to light" : "Switch to dark"}
          className="grid h-8 w-8 place-items-center rounded-md border text-muted-foreground hover:bg-accent hover:text-foreground"
        >
          {theme === "dark" ? <Sun className="h-3.5 w-3.5" /> : <Moon className="h-3.5 w-3.5" />}
        </button>
      </header>

      {/* Mobile drawer */}
      {mobileOpen && (
        <div className="fixed inset-0 z-40 lg:hidden" role="dialog" aria-modal="true" aria-label="Navigation">
          <div
            className="absolute inset-0 bg-black/50 backdrop-blur-[1px]"
            onClick={() => setMobileOpen(false)}
            aria-hidden="true"
          />
          <aside
            className={cn(
              "absolute left-0 top-0 flex h-svh w-72 max-w-[85vw] flex-col border-r bg-sidebar text-sidebar-foreground shadow-xl",
              "animate-in slide-in-from-left duration-200",
            )}
          >
            <div className="flex items-center justify-between border-b px-3 py-2">
              <span className="text-xs font-medium text-muted-foreground">Navigation</span>
              <button
                type="button"
                onClick={() => setMobileOpen(false)}
                aria-label="Close navigation"
                className="grid h-7 w-7 place-items-center rounded-md hover:bg-sidebar-accent"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            </div>
            <div className="flex-1 overflow-hidden">
              <SidebarBody repoKey={repoKey} onNavigate={() => setMobileOpen(false)} />
            </div>
            <SidebarFooter theme={theme} toggle={toggle} />
          </aside>
        </div>
      )}

      {/* Desktop sidebar */}
      <aside className="hidden h-svh w-64 shrink-0 flex-col border-r bg-sidebar text-sidebar-foreground lg:flex">
        <div className="flex flex-1 flex-col overflow-hidden">
          <SidebarBody repoKey={repoKey} />
        </div>
        <SidebarFooter theme={theme} toggle={toggle} />
      </aside>
    </>
  );
}

function SidebarFooter({ theme, toggle }: { theme: "light" | "dark"; toggle: () => void }) {
  return (
    <div className="flex items-center justify-between gap-2 border-t px-3 py-2">
      <button
        type="button"
        className="flex items-center gap-2 rounded-md px-1.5 py-1 transition-colors hover:bg-sidebar-accent"
      >
        <span className="grid h-6 w-6 place-items-center rounded-full bg-rose-500 text-[10px] font-medium text-white">
          AM
        </span>
        <span className="text-sm">Ava Martinez</span>
      </button>
      <button
        onClick={toggle}
        aria-label="Toggle theme"
        title={theme === "dark" ? "Switch to light" : "Switch to dark"}
        className="grid h-7 w-7 place-items-center rounded-md text-muted-foreground hover:bg-sidebar-accent hover:text-foreground"
      >
        {theme === "dark" ? <Sun className="h-3.5 w-3.5" /> : <Moon className="h-3.5 w-3.5" />}
      </button>
    </div>
  );
}
