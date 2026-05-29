"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import {
  ChevronRight,
  FileText,
  GitBranch,
  Plus,
  Trash2,
} from "lucide-react";
import type {
  SpecArtifact,
  SpecArtifactSummary,
  SpecArtifactType,
  SpecWorkspacePayload,
  SpecWorkspaceSection,
} from "@/lib/repository-model";
import { useDocs, type DocPage } from "@/lib/docs-store";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { cn } from "@/lib/utils";

interface Props {
  repoKey: string;
}

const WORKSPACE_GROUPS = [
  { label: "Codebase", sectionLabels: ["Codebase"], createTypes: [] },
  {
    label: "Milestone",
    sectionLabels: ["Milestones", "Discussions", "Requirements", "Task proposals", "Task briefs"],
    createTypes: ["milestone", "discussion", "requirements", "task_proposal", "task_brief"],
  },
  { label: "Plans", sectionLabels: ["Plans"], createTypes: ["plan"] },
  { label: "Decisions", sectionLabels: ["Decisions"], createTypes: ["decision"] },
] satisfies Array<{
  label: string;
  sectionLabels: string[];
  createTypes: SpecArtifactType[];
}>;

const SPEC_TYPE_LABELS: Record<SpecArtifactType, string> = {
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
};

/**
 * Notion-like document tree, scoped to one repository.
 *
 * Planning artifacts are shown as private workspace sections. Repository rules
 * are a pinned root link.
 */
export function DocTree({ repoKey }: Props) {
  const pathname = usePathname();
  const router = useRouter();
  const slug = repoKey.toLowerCase();
  const {
    archivePage,
    createPage,
    forRepo,
    hydrated,
  } = useDocs();
  const [specWorkspace, setSpecWorkspace] = useState<SpecWorkspacePayload | null>(null);
  const [specPending, setSpecPending] = useState<string | null>(null);
  const [specError, setSpecError] = useState<string | null>(null);
  const [pagePending, setPagePending] = useState<string | null>(null);

  const docPages = useMemo(
    () =>
      forRepo(repoKey)
        .filter((page) => page.category === "doc")
        .sort((a, b) => a.createdAt - b.createdAt),
    [forRepo, repoKey],
  );
  const loadSpecWorkspace = useCallback(async () => {
    const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/spec-workspace`, {
      cache: "no-store",
    });
    const payload = (await res.json()) as {
      specWorkspace?: SpecWorkspacePayload;
      error?: string;
    };
    if (!res.ok || !payload.specWorkspace) {
      throw new Error(payload.error ?? "Could not load planning documents");
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
        setSpecError(err instanceof Error ? err.message : "Could not load planning documents");
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
        throw new Error(payload.error ?? "Could not set up planning documents");
      }
      setSpecWorkspace(payload.specWorkspace);
    } catch (err) {
      setSpecError(err instanceof Error ? err.message : "Could not set up planning documents");
    } finally {
      setSpecPending(null);
    }
  };

  const createSpecArtifact = async (type: SpecArtifactType) => {
    const pendingKey = `spec-create:${type}`;
    setSpecPending(pendingKey);
    setSpecError(null);
    try {
      const res = await fetch(
        `/api/repositories/${encodeURIComponent(repoKey)}/spec-workspace/artifacts/${encodeURIComponent(
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
      await loadSpecWorkspace();
      router.push(specArtifactHref(slug, payload.artifact));
    } catch (err) {
      setSpecError(err instanceof Error ? err.message : "Could not create workspace document");
    } finally {
      setSpecPending(null);
    }
  };

  const createUntitledPage = async (parentId?: string) => {
    const pendingKey = `create:${parentId ?? "root"}`;
    setPagePending(pendingKey);
    try {
      const page = await createPage(repoKey, "doc", {
        title: "Untitled",
        body: "",
        parentId,
      });
      router.push(`/r/${slug}/docs/${encodeURIComponent(page.id)}`);
    } finally {
      setPagePending(null);
    }
  };

  const archiveDocPage = async (page: DocPage) => {
    setPagePending(`archive:${page.id}`);
    try {
      await archivePage(page.id);
      if (pathname === `/r/${slug}/docs/${page.id}`) {
        router.push(`/r/${slug}`);
      }
    } finally {
      setPagePending(null);
    }
  };

  return (
    <div className="space-y-3 text-[13px]">
      {/* Repository rules are pinned, not a section. */}
      <SidebarLink
        href={`/r/${slug}/workflow`}
        active={pathname === `/r/${slug}/workflow`}
        icon={<GitBranch className="h-3.5 w-3.5" />}
        label="Repository rules"
        right={
          <span className="text-[10px] font-mono text-muted-foreground">root</span>
        }
      />

      <PageTreeSection
        repoSlug={slug}
        currentPath={pathname}
        pages={docPages}
        hydrated={hydrated}
        pending={pagePending}
        onCreate={createUntitledPage}
        onArchive={archiveDocPage}
      />

      {specError && (
        <p className="rounded-md border border-amber-500/30 bg-amber-500/10 px-2 py-1 text-[11px] text-amber-700 dark:text-amber-300">
          {specError}
        </p>
      )}

      {specWorkspace?.state.initialized ? (
        <div className="space-y-2">
          {WORKSPACE_GROUPS.map((group) => {
            const artifacts = group.sectionLabels.flatMap(
              (label) =>
                specWorkspace.sections.find((section) => section.label === label)?.artifacts ?? [],
            );

            return (
              <SpecArtifactSection
                key={group.label}
                label={group.label}
                artifacts={artifacts}
                createTypes={group.createTypes}
                pending={specPending}
                repoSlug={slug}
                currentPath={pathname}
                onCreate={createSpecArtifact}
              />
            );
          })}
        </div>
      ) : (
        <div className="rounded-md border border-dashed px-2 py-2">
          <p className="text-[11px] text-muted-foreground">Set up planning documents for this repository.</p>
          <button
            onClick={initializeSpecWorkspace}
            disabled={specPending === "initialize"}
            className="mt-2 rounded-md border bg-background px-2 py-1 text-[11px] hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
          >
            {specPending === "initialize" ? "Creating..." : "Set up planning docs"}
          </button>
        </div>
      )}
    </div>
  );
}

function PageTreeSection({
  repoSlug,
  currentPath,
  pages,
  hydrated,
  pending,
  onCreate,
  onArchive,
}: {
  repoSlug: string;
  currentPath: string;
  pages: DocPage[];
  hydrated: boolean;
  pending: string | null;
  onCreate: (parentId?: string) => Promise<void>;
  onArchive: (page: DocPage) => Promise<void>;
}) {
  const { childrenByParent, rootPages } = useMemo(() => {
    const ids = new Set(pages.map((page) => page.id));
    const grouped = new Map<string, DocPage[]>();

    for (const page of pages) {
      const parentKey = page.parentId && ids.has(page.parentId) ? page.parentId : "root";
      const children = grouped.get(parentKey) ?? [];
      children.push(page);
      grouped.set(parentKey, children);
    }

    for (const children of grouped.values()) {
      children.sort((a, b) => a.createdAt - b.createdAt);
    }

    return {
      childrenByParent: grouped,
      rootPages: grouped.get("root") ?? [],
    };
  }, [pages]);

  return (
    <section className="space-y-1">
      <div className="px-1.5">
        <span className="text-[11px] font-semibold uppercase tracking-[0.08em] text-muted-foreground">
          Pages
        </span>
      </div>

      {!hydrated ? (
        <div className="px-1.5 py-1 text-[12px] text-muted-foreground">Loading pages...</div>
      ) : rootPages.length === 0 ? (
        <button
          type="button"
          onClick={() => void onCreate()}
          disabled={pending === "create:root"}
          className="flex w-full items-center gap-1.5 rounded-md px-1.5 py-1 text-left text-muted-foreground transition-colors hover:bg-sidebar-accent hover:text-foreground disabled:cursor-not-allowed disabled:opacity-50"
        >
          <FileText className="h-3.5 w-3.5" />
          <span className="flex-1 truncate">Add a page</span>
        </button>
      ) : (
        <ul className="space-y-0.5">
          {rootPages.map((page) => (
            <PageTreeNode
              key={page.id}
              page={page}
              repoSlug={repoSlug}
              currentPath={currentPath}
              childrenByParent={childrenByParent}
              pending={pending}
              depth={0}
              onCreate={onCreate}
              onArchive={onArchive}
            />
          ))}
        </ul>
      )}
    </section>
  );
}

function PageTreeNode({
  page,
  repoSlug,
  currentPath,
  childrenByParent,
  pending,
  depth,
  onCreate,
  onArchive,
}: {
  page: DocPage;
  repoSlug: string;
  currentPath: string;
  childrenByParent: Map<string, DocPage[]>;
  pending: string | null;
  depth: number;
  onCreate: (parentId?: string) => Promise<void>;
  onArchive: (page: DocPage) => Promise<void>;
}) {
  const href = pageHref(repoSlug, page);
  const children = childrenByParent.get(page.id) ?? [];
  const hasChildren = children.length > 0;
  const active = currentPath === href;
  const activeDescendant = hasActiveDescendant(children, childrenByParent, currentPath, repoSlug);
  const [open, setOpen] = useState(activeDescendant);

  useEffect(() => {
    if (activeDescendant) setOpen(true);
  }, [activeDescendant]);

  return (
    <li>
      <div
        className={cn(
          "group flex items-center gap-0.5 rounded-md pr-1 transition-colors",
          active
            ? "bg-sidebar-accent text-sidebar-accent-foreground"
            : "text-muted-foreground hover:bg-sidebar-accent hover:text-foreground",
        )}
        style={{ paddingLeft: `${depth * 12 + 2}px` }}
      >
        <button
          type="button"
          onClick={() => hasChildren && setOpen((value) => !value)}
          disabled={!hasChildren}
          aria-label={open ? "Collapse page" : "Expand page"}
          className={cn(
            "grid h-6 w-4 place-items-center rounded text-muted-foreground",
            hasChildren ? "hover:text-foreground" : "opacity-0",
          )}
        >
          <ChevronRight className={cn("h-3 w-3 transition-transform", open && "rotate-90")} />
        </button>
        <Link href={href} className="flex min-w-0 flex-1 items-center gap-1.5 py-1">
          <PageIcon page={page} />
          <span className="truncate">
            {page.title || <span className="italic text-muted-foreground/70">Untitled</span>}
          </span>
        </Link>
        <button
          type="button"
          onClick={() => void onCreate(page.id)}
          disabled={pending === `create:${page.id}`}
          aria-label={`Add page inside ${page.title || "Untitled"}`}
          title="Add page inside"
          className="grid h-6 w-6 shrink-0 place-items-center rounded-[8px] text-muted-foreground opacity-0 transition hover:bg-background/70 hover:text-foreground group-hover:opacity-100 focus:opacity-100 disabled:cursor-not-allowed disabled:opacity-50"
        >
          <Plus className="h-3.5 w-3.5" />
        </button>
        <button
          type="button"
          onClick={() => void onArchive(page)}
          disabled={pending === `archive:${page.id}`}
          aria-label={`Delete ${page.title || "Untitled"}`}
          title="Delete"
          className="grid h-6 w-6 shrink-0 place-items-center rounded-[8px] text-muted-foreground opacity-0 transition hover:bg-background/70 hover:text-foreground group-hover:opacity-100 focus:opacity-100 disabled:cursor-not-allowed disabled:opacity-50"
        >
          <Trash2 className="h-3.5 w-3.5" />
        </button>
      </div>

      {hasChildren && open && (
        <ul className="mt-0.5 space-y-0.5">
          {children.map((child) => (
            <PageTreeNode
              key={child.id}
              page={child}
              repoSlug={repoSlug}
              currentPath={currentPath}
              childrenByParent={childrenByParent}
              pending={pending}
              depth={depth + 1}
              onCreate={onCreate}
              onArchive={onArchive}
            />
          ))}
        </ul>
      )}
    </li>
  );
}

function PageIcon({ page }: { page: DocPage }) {
  if (page.icon) return <span className="shrink-0 text-sm leading-none">{page.icon}</span>;
  return <FileText className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />;
}

function pageHref(repoSlug: string, page: DocPage) {
  return `/r/${repoSlug}/docs/${encodeURIComponent(page.id)}`;
}

function hasActiveDescendant(
  pages: DocPage[],
  childrenByParent: Map<string, DocPage[]>,
  currentPath: string,
  repoSlug: string,
): boolean {
  return pages.some((page) => {
    if (currentPath === pageHref(repoSlug, page)) return true;
    return hasActiveDescendant(childrenByParent.get(page.id) ?? [], childrenByParent, currentPath, repoSlug);
  });
}

function SpecArtifactSection({
  label,
  artifacts,
  createTypes,
  pending,
  repoSlug,
  currentPath,
  onCreate,
}: {
  label: string;
  artifacts: SpecWorkspaceSection["artifacts"];
  createTypes: SpecArtifactType[];
  pending: string | null;
  repoSlug: string;
  currentPath: string;
  onCreate: (type: SpecArtifactType) => Promise<void>;
}) {
  const hasActiveArtifact = artifacts.some(
    (artifact) => currentPath === specArtifactHref(repoSlug, artifact),
  );
  const [open, setOpen] = useState(hasActiveArtifact);

  useEffect(() => {
    if (hasActiveArtifact) setOpen(true);
  }, [hasActiveArtifact]);

  if (artifacts.length === 0 && createTypes.length === 0) return null;

  return (
    <section>
      <div className="group flex items-center gap-1">
        <button
          type="button"
          onClick={() => setOpen((value) => !value)}
          aria-expanded={open}
          className={cn(
            "flex min-w-0 flex-1 items-center gap-1 rounded-md px-1.5 py-1 text-left text-[11px] font-semibold uppercase tracking-[0.08em] text-muted-foreground transition-colors hover:bg-sidebar-accent hover:text-foreground",
            hasActiveArtifact && "text-foreground",
          )}
        >
          <ChevronRight className={cn("h-3 w-3 transition-transform", open && "rotate-90")} />
          <span className="flex-1 truncate">{label}</span>
        </button>
        {createTypes.length > 0 && (
          <SpecCreateMenu
            createTypes={createTypes}
            pending={pending}
            onCreate={onCreate}
          />
        )}
      </div>
      {open && (
        <ul className="mt-1 border-l pl-1.5">
          {artifacts.map((artifact) => (
            <SpecArtifactNode
              key={`${artifact.type}:${artifact.id}`}
              artifact={artifact}
              repoSlug={repoSlug}
              active={currentPath === specArtifactHref(repoSlug, artifact)}
            />
          ))}
        </ul>
      )}
    </section>
  );
}

function SpecCreateMenu({
  createTypes,
  pending,
  onCreate,
}: {
  createTypes: SpecArtifactType[];
  pending: string | null;
  onCreate: (type: SpecArtifactType) => Promise<void>;
}) {
  if (createTypes.length === 1) {
    const type = createTypes[0];
    return (
      <button
        type="button"
        onClick={() => void onCreate(type)}
        disabled={pending === `spec-create:${type}`}
        aria-label={`New ${SPEC_TYPE_LABELS[type]}`}
        title={`New ${SPEC_TYPE_LABELS[type]}`}
        className="grid h-6 w-6 shrink-0 place-items-center rounded-[8px] text-muted-foreground opacity-0 transition-colors hover:bg-sidebar-accent hover:text-foreground focus:opacity-100 group-hover:opacity-100 disabled:cursor-not-allowed disabled:opacity-50"
      >
        <Plus className="h-3.5 w-3.5" />
      </button>
    );
  }

  return (
    <Popover>
      <PopoverTrigger asChild>
        <button
          type="button"
          aria-label="New workspace document"
          title="New workspace document"
          className="grid h-6 w-6 shrink-0 place-items-center rounded-[8px] text-muted-foreground opacity-0 transition-colors hover:bg-sidebar-accent hover:text-foreground focus:opacity-100 group-hover:opacity-100"
        >
          <Plus className="h-3.5 w-3.5" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-52 p-1">
        {createTypes.map((type) => (
          <button
            key={type}
            type="button"
            onClick={() => void onCreate(type)}
            disabled={pending === `spec-create:${type}`}
            className="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-[12px] text-muted-foreground transition-colors hover:bg-accent hover:text-foreground disabled:cursor-not-allowed disabled:opacity-50"
          >
            <FileText className="h-3.5 w-3.5" />
            New {SPEC_TYPE_LABELS[type]}
          </button>
        ))}
      </PopoverContent>
    </Popover>
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
