"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
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
  BookOpen,
  Landmark,
  ListChecks,
  MessageSquareText,
  Milestone,
} from "lucide-react";
import {
  CATEGORY_LABELS,
  useDocs,
  type DocCategory,
  type DocPage,
} from "@/lib/docs-store";
import type {
  SpecArtifact,
  SpecArtifactStatus,
  SpecArtifactSummary,
  SpecArtifactType,
  SpecWorkspacePayload,
  SpecWorkspaceSection,
} from "@/lib/repository-model";
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
  { category: "review", href: (s) => `/r/${s}/reviews`, icon: ScrollText },
  { category: "run-summary", href: (s) => `/r/${s}/run-summaries`, icon: Activity },
];

const SPEC_SECTION_ICONS: Record<string, typeof FileText> = {
  Codebase: BookOpen,
  Milestones: Milestone,
  Discussions: MessageSquareText,
  Requirements: ListChecks,
  Plans: ShieldCheck,
  Decisions: Landmark,
};

const SPEC_TYPE_LABELS: Record<SpecArtifactType, string> = {
  codebase_map: "Codebase map",
  codebase_conventions: "Conventions",
  codebase_architecture: "Architecture",
  milestone: "Milestone",
  discussion: "Discussion",
  requirements: "Requirements",
  plan: "Plan",
  decision: "Decision",
};

const SPEC_STATUS_LABELS: Record<SpecArtifactStatus, string> = {
  draft: "Draft",
  in_discussion: "In discussion",
  requirements_ready: "Requirements ready",
  plan_ready: "Plan ready",
  ready_for_approval: "Ready for approval",
  approved: "Approved",
  archived: "Archived",
};

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
  const [specWorkspace, setSpecWorkspace] = useState<SpecWorkspacePayload | null>(null);
  const [specPending, setSpecPending] = useState<string | null>(null);
  const [specError, setSpecError] = useState<string | null>(null);

  const loadSpecWorkspace = useCallback(async () => {
    const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/spec-workspace`, {
      cache: "no-store",
    });
    const payload = (await res.json()) as {
      specWorkspace?: SpecWorkspacePayload;
      error?: string;
    };
    if (!res.ok || !payload.specWorkspace) {
      throw new Error(payload.error ?? "Could not load workspace files");
    }
    setSpecWorkspace(payload.specWorkspace);
    setSpecError(null);
    return payload.specWorkspace;
  }, [repoKey]);

  useEffect(() => {
    let cancelled = false;
    loadSpecWorkspace().catch((err: unknown) => {
      if (!cancelled) {
        setSpecWorkspace(null);
        setSpecError(err instanceof Error ? err.message : "Could not load workspace files");
      }
    });

    const handler = (event: Event) => {
      const detail = (event as CustomEvent<{ repoKey: string }>).detail;
      if (detail?.repoKey === repoKey) void loadSpecWorkspace();
    };
    window.addEventListener("symphonia:specWorkspaceChanged", handler as EventListener);

    return () => {
      cancelled = true;
      window.removeEventListener("symphonia:specWorkspaceChanged", handler as EventListener);
    };
  }, [loadSpecWorkspace, repoKey]);

  const initializeSpecWorkspace = async () => {
    setSpecPending("initialize");
    setSpecError(null);
    try {
      const res = await fetch(
        `/api/repositories/${encodeURIComponent(repoKey)}/spec-workspace/initialize`,
        { method: "POST" },
      );
      const payload = (await res.json()) as {
        specWorkspace?: SpecWorkspacePayload;
        error?: string;
      };
      if (!res.ok || !payload.specWorkspace) {
        throw new Error(payload.error ?? "Could not create spec workspace");
      }
      setSpecWorkspace(payload.specWorkspace);
    } catch (err) {
      setSpecError(err instanceof Error ? err.message : "Could not create spec workspace");
    } finally {
      setSpecPending(null);
    }
  };

  const createSpecArtifact = async (kind: "milestones" | "decisions") => {
    setSpecPending(kind);
    setSpecError(null);
    try {
      const res = await fetch(
        `/api/repositories/${encodeURIComponent(repoKey)}/spec-workspace/${kind}`,
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({}),
        },
      );
      const payload = (await res.json()) as { artifact?: SpecArtifact; error?: string };
      if (!res.ok || !payload.artifact) {
        throw new Error(payload.error ?? "Could not create workspace file");
      }
      await loadSpecWorkspace();
      router.push(specArtifactHref(slug, payload.artifact));
    } catch (err) {
      setSpecError(err instanceof Error ? err.message : "Could not create workspace file");
    } finally {
      setSpecPending(null);
    }
  };

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

      {specError && (
        <p className="rounded-md border border-amber-500/30 bg-amber-500/10 px-2 py-1 text-[11px] text-amber-700 dark:text-amber-300">
          {specError}
        </p>
      )}

      {specWorkspace?.state.initialized ? (
        specWorkspace.sections.map((section) => {
          const Icon = SPEC_SECTION_ICONS[section.label] ?? FileText;
          const onAdd =
            section.label === "Milestones"
              ? () => createSpecArtifact("milestones")
              : section.label === "Decisions"
                ? () => createSpecArtifact("decisions")
                : undefined;

          return (
            <SpecArtifactSection
              key={section.label}
              section={section}
              icon={<Icon className="h-3.5 w-3.5" />}
              repoSlug={slug}
              currentPath={pathname}
              onAdd={onAdd}
              pending={specPending === "milestones" || specPending === "decisions"}
            />
          );
        })
      ) : (
        <div className="rounded-md border border-dashed px-2 py-2">
          <p className="text-[11px] text-muted-foreground">
            Create a spec workspace for this repository.
          </p>
          <button
            onClick={initializeSpecWorkspace}
            disabled={specPending === "initialize"}
            className="mt-2 rounded-md border bg-background px-2 py-1 text-[11px] hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
          >
            {specPending === "initialize" ? "Creating..." : "Create Spec Workspace"}
          </button>
        </div>
      )}

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

function SpecArtifactSection({
  section,
  icon,
  repoSlug,
  currentPath,
  onAdd,
  pending,
}: {
  section: SpecWorkspaceSection;
  icon: React.ReactNode;
  repoSlug: string;
  currentPath: string;
  onAdd?: () => void;
  pending?: boolean;
}) {
  const [open, setOpen] = useState(true);

  return (
    <div>
      <div className="group flex items-center gap-1 rounded-md px-1.5 py-1 text-muted-foreground">
        <button
          onClick={() => setOpen((v) => !v)}
          aria-expanded={open}
          aria-label={`${open ? "Collapse" : "Expand"} ${section.label}`}
          className="grid h-4 w-4 place-items-center rounded hover:bg-accent"
        >
          <ChevronRight className={cn("h-3 w-3 transition-transform", open && "rotate-90")} />
        </button>
        <div className="flex flex-1 items-center gap-1.5 truncate">
          {icon}
          <span className="truncate">{section.label}</span>
          {section.artifacts.length > 0 && (
            <span className="ml-auto text-[10px] tabular-nums text-muted-foreground/70">
              {section.artifacts.length}
            </span>
          )}
        </div>
        {onAdd && (
          <button
            onClick={onAdd}
            disabled={pending}
            aria-label={`New ${section.label}`}
            title={`New ${section.label.replace(/s$/, "")}`}
            className="grid h-4 w-4 place-items-center rounded opacity-0 group-hover:opacity-100 hover:bg-accent disabled:cursor-not-allowed disabled:opacity-50 text-muted-foreground hover:text-foreground"
          >
            <Plus className="h-3 w-3" />
          </button>
        )}
      </div>
      {open && (
        <ul className="ml-3 mt-0.5 border-l pl-1.5">
          {section.artifacts.length === 0 ? (
            <li className="px-2 py-1 text-[11px] text-muted-foreground/70">
              Empty{onAdd ? " - click + to add one" : ""}
            </li>
          ) : (
            section.artifacts.map((artifact) => (
              <SpecArtifactNode
                key={`${artifact.type}:${artifact.id}`}
                artifact={artifact}
                repoSlug={repoSlug}
                active={currentPath === specArtifactHref(repoSlug, artifact)}
              />
            ))
          )}
        </ul>
      )}
    </div>
  );
}

function SpecArtifactNode({
  artifact,
  repoSlug,
  active,
}: {
  artifact: SpecArtifactSummary;
  repoSlug: string;
  active: boolean;
}) {
  return (
    <li>
      <Link
        href={specArtifactHref(repoSlug, artifact)}
        className={cn(
          "block rounded-md px-1.5 py-1 text-muted-foreground hover:bg-sidebar-accent hover:text-foreground",
          active && "bg-sidebar-accent text-sidebar-accent-foreground",
        )}
      >
        <span className="block truncate">
          {artifact.title || (
            <span className="italic text-muted-foreground/70">Untitled</span>
          )}
        </span>
        <span className="mt-0.5 flex items-center justify-between gap-2 text-[10px] text-muted-foreground/70">
          <span className="truncate">{SPEC_TYPE_LABELS[artifact.type]}</span>
          <span>{SPEC_STATUS_LABELS[artifact.status]}</span>
        </span>
      </Link>
    </li>
  );
}

function specArtifactHref(
  slug: string,
  artifact: Pick<SpecArtifactSummary, "type" | "id">,
) {
  return `/r/${slug}/workspace/${encodeURIComponent(artifact.type)}/${encodeURIComponent(
    artifact.id,
  )}`;
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
