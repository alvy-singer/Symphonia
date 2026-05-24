"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import {
  ChevronRight,
  FileText,
  Folder,
  GitBranch,
  KanbanSquare,
  Layers,
  Plus,
  ScrollText,
  ShieldCheck,
  Sparkles,
  Activity,
} from "lucide-react";
import {
  CATEGORY_LABELS,
  useDocs,
  type DocCategory,
  type DocPage,
} from "@/lib/docs-store";
import { cn } from "@/lib/utils";

interface Props {
  repoKey: string;
  /** Called when user picks "New <category>" — opens a draft. */
  onNew: (category: DocCategory) => void;
}

const SECTIONS: {
  category: DocCategory;
  href: (slug: string) => string;
  icon: typeof Folder;
}[] = [
  { category: "project", href: (s) => `/r/${s}/projects`, icon: KanbanSquare },
  { category: "task", href: (s) => `/r/${s}/tasks`, icon: Layers },
  { category: "doc", href: (s) => `/r/${s}/docs`, icon: FileText },
  { category: "decision", href: (s) => `/r/${s}/decisions`, icon: ShieldCheck },
  { category: "review", href: (s) => `/r/${s}/reviews`, icon: ScrollText },
  { category: "run-summary", href: (s) => `/r/${s}/run-summaries`, icon: Activity },
];

/**
 * Notion-like document tree, scoped to one repository.
 *
 * Each section is a category. Docs and Decisions support nested children.
 * Tasks/Projects/Reviews/Run Summaries are flat lists. Workflow is a single
 * pinned link to root WORKFLOW.md.
 */
export function DocTree({ repoKey, onNew }: Props) {
  const { forRepo } = useDocs();
  const router = useRouter();
  const pathname = usePathname();
  const slug = repoKey.toLowerCase();
  const pages = useMemo(() => forRepo(repoKey), [forRepo, repoKey]);

  return (
    <div className="space-y-3 text-[13px]">
      {/* Workflow is pinned, not a section. */}
      <SidebarLink
        href={`/r/${slug}/workflow`}
        active={pathname === `/r/${slug}/workflow`}
        icon={<GitBranch className="h-3.5 w-3.5" />}
        label="WORKFLOW.md"
        right={
          <span className="text-[10px] font-mono text-muted-foreground">root</span>
        }
      />

      {SECTIONS.map((s) => {
        const Icon = s.icon;
        const sectionPages = pages.filter((p) => p.category === s.category);
        const sectionHref = s.href(slug);
        const sectionActive = pathname === sectionHref;
        return (
          <CategorySection
            key={s.category}
            label={CATEGORY_LABELS[s.category]}
            icon={<Icon className="h-3.5 w-3.5" />}
            href={sectionHref}
            active={sectionActive}
            count={sectionPages.length}
            onAdd={() => onNew(s.category)}
            pages={sectionPages}
            repoSlug={slug}
            currentPath={pathname}
            onOpen={(p) => router.push(pageHref(slug, p))}
          />
        );
      })}

      <SidebarLink
        href="#"
        onClickAction={() => onNew("doc")}
        icon={<Sparkles className="h-3.5 w-3.5" />}
        label="Ask Clarise to draft"
        muted
      />
    </div>
  );
}

function pageHref(slug: string, p: DocPage): string {
  switch (p.category) {
    case "task":
      // Tasks are listed by repo; deep-link uses the page id.
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

function CategorySection({
  label,
  icon,
  href,
  active,
  count,
  onAdd,
  pages,
  repoSlug,
  currentPath,
  onOpen,
}: {
  label: string;
  icon: React.ReactNode;
  href: string;
  active: boolean;
  count: number;
  onAdd: () => void;
  pages: DocPage[];
  repoSlug: string;
  currentPath: string;
  onOpen: (p: DocPage) => void;
}) {
  const [open, setOpen] = useState(true);
  const roots = pages.filter((p) => !p.parentId);

  return (
    <div>
      <div
        className={cn(
          "group flex items-center gap-1 rounded-md px-1.5 py-1 text-muted-foreground",
          active && "bg-sidebar-accent text-sidebar-accent-foreground",
        )}
      >
        <button
          onClick={() => setOpen((v) => !v)}
          aria-expanded={open}
          aria-label={`${open ? "Collapse" : "Expand"} ${label}`}
          className="grid h-4 w-4 place-items-center rounded hover:bg-accent"
        >
          <ChevronRight
            className={cn(
              "h-3 w-3 transition-transform",
              open && "rotate-90",
            )}
          />
        </button>
        <Link
          href={href}
          className="flex flex-1 items-center gap-1.5 truncate hover:text-foreground"
        >
          {icon}
          <span className="truncate">{label}</span>
          {count > 0 && (
            <span className="ml-auto text-[10px] tabular-nums text-muted-foreground/70">
              {count}
            </span>
          )}
        </Link>
        <button
          onClick={onAdd}
          aria-label={`New ${label}`}
          title={`New ${label.replace(/s$/, "")}`}
          className="grid h-4 w-4 place-items-center rounded opacity-0 group-hover:opacity-100 hover:bg-accent text-muted-foreground hover:text-foreground"
        >
          <Plus className="h-3 w-3" />
        </button>
      </div>
      {open && (
        <ul className="ml-3 mt-0.5 border-l pl-1.5">
          {roots.length === 0 ? (
            <li className="px-2 py-1 text-[11px] text-muted-foreground/70">
              Empty — click + to add one
            </li>
          ) : (
            roots.map((p) => (
              <PageNode
                key={p.id}
                page={p}
                allPages={pages}
                repoSlug={repoSlug}
                currentPath={currentPath}
                depth={0}
                onOpen={onOpen}
              />
            ))
          )}
        </ul>
      )}
    </div>
  );
}

function PageNode({
  page,
  allPages,
  repoSlug,
  currentPath,
  depth,
  onOpen,
}: {
  page: DocPage;
  allPages: DocPage[];
  repoSlug: string;
  currentPath: string;
  depth: number;
  onOpen: (p: DocPage) => void;
}) {
  const children = allPages.filter((p) => p.parentId === page.id);
  const [open, setOpen] = useState(true);
  const href = pageHref(repoSlug, page);
  const active = currentPath === href;

  return (
    <li>
      <div
        className={cn(
          "group flex items-center gap-1 rounded-md px-1.5 py-1 text-muted-foreground",
          active && "bg-sidebar-accent text-sidebar-accent-foreground",
        )}
        style={{ paddingLeft: depth * 8 + 6 }}
      >
        {children.length > 0 ? (
          <button
            onClick={() => setOpen((v) => !v)}
            aria-expanded={open}
            aria-label={open ? "Collapse" : "Expand"}
            className="grid h-4 w-4 place-items-center rounded hover:bg-accent"
          >
            <ChevronRight
              className={cn(
                "h-3 w-3 transition-transform",
                open && "rotate-90",
              )}
            />
          </button>
        ) : (
          <span className="inline-block w-4" aria-hidden />
        )}
        <button
          onClick={() => onOpen(page)}
          className="flex flex-1 items-center gap-1.5 truncate hover:text-foreground text-left"
        >
          <span aria-hidden className="text-[12px] leading-none">
            {page.icon ?? "·"}
          </span>
          <span className="truncate">
            {page.title || (
              <span className="italic text-muted-foreground/70">Untitled</span>
            )}
          </span>
        </button>
      </div>
      {open && children.length > 0 && (
        <ul>
          {children.map((c) => (
            <PageNode
              key={c.id}
              page={c}
              allPages={allPages}
              repoSlug={repoSlug}
              currentPath={currentPath}
              depth={depth + 1}
              onOpen={onOpen}
            />
          ))}
        </ul>
      )}
    </li>
  );
}

function SidebarLink({
  href,
  active,
  icon,
  label,
  right,
  onClickAction,
  muted,
}: {
  href: string;
  active?: boolean;
  icon: React.ReactNode;
  label: string;
  right?: React.ReactNode;
  onClickAction?: () => void;
  muted?: boolean;
}) {
  const className = cn(
    "flex items-center gap-1.5 rounded-md px-1.5 py-1 transition-colors",
    active
      ? "bg-sidebar-accent text-sidebar-accent-foreground"
      : muted
        ? "text-muted-foreground/70 hover:bg-sidebar-accent hover:text-foreground"
        : "text-muted-foreground hover:bg-sidebar-accent hover:text-foreground",
  );
  if (onClickAction) {
    return (
      <button onClick={onClickAction} className={cn(className, "w-full text-left")}>
        {icon}
        <span className="flex-1 truncate">{label}</span>
        {right}
      </button>
    );
  }
  return (
    <Link href={href} className={className}>
      {icon}
      <span className="flex-1 truncate">{label}</span>
      {right}
    </Link>
  );
}
