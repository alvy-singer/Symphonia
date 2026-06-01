"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import {
  ChevronRight,
  GitBranch,
  Trash2,
} from "lucide-react";
import type {
  SpecArtifact,
  SpecArtifactSummary,
  SpecWorkspacePayload,
  SpecWorkspaceSection,
} from "@/lib/repository-model";
import { cn } from "@/lib/utils";

interface Props {
  repoKey: string;
  onNavigate?: () => void;
}

const WORKSPACE_GROUPS = [
  { label: "Codebase", sectionLabels: ["Codebase"] },
  {
    label: "Milestones",
    sectionLabels: ["Milestones"],
  },
  { label: "Plans", sectionLabels: ["Plans"] },
  { label: "Decisions", sectionLabels: ["Decisions"] },
  { label: "Run summaries", sectionLabels: ["Run summaries"] },
] satisfies Array<{
  label: string;
  sectionLabels: string[];
}>;

const EXPORT_STATUS_LABELS: Record<string, string> = {
  never_exported: "Private",
  linked: "Linked",
  changed_since_export: "Changed",
  pr_open: "PR open",
  conflict: "Conflict",
  unlinked: "Unlinked",
};

/**
 * Notion-like document tree, scoped to one repository.
 *
 * Planning artifacts and repository rules are shown as workspace files.
 */
export function DocTree({ repoKey, onNavigate }: Props) {
  const pathname = usePathname();
  const router = useRouter();
  const slug = repoKey.toLowerCase();
  const [specWorkspace, setSpecWorkspace] = useState<SpecWorkspacePayload | null>(null);
  const [specPending, setSpecPending] = useState<string | null>(null);
  const [specError, setSpecError] = useState<string | null>(null);

  const loadSpecWorkspace = useCallback(async () => {
    const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/private-workspace`, {
      cache: "no-store",
    });
    const payload = (await res.json()) as {
      privateWorkspace?: SpecWorkspacePayload;
      error?: string;
    };
    if (!res.ok || !payload.privateWorkspace) {
      throw new Error(payload.error ?? "Could not load planning documents");
    }
    setSpecWorkspace(payload.privateWorkspace);
    return payload.privateWorkspace;
  }, [repoKey]);

  useEffect(() => {
    let cancelled = false;
    loadSpecWorkspace().catch(() => {
      if (!cancelled) {
        setSpecWorkspace(null);
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
        `/api/repositories/${encodeURIComponent(repoKey)}/private-workspace/initialize`,
        { method: "POST" },
      );
      const payload = (await res.json()) as {
        privateWorkspace?: SpecWorkspacePayload;
        error?: string;
      };
      if (!res.ok || !payload.privateWorkspace) {
        throw new Error(payload.error ?? "Could not set up planning documents");
      }
      setSpecWorkspace(payload.privateWorkspace);
      window.dispatchEvent(new CustomEvent("symphonia:specWorkspaceChanged", { detail: { repoKey } }));
      window.dispatchEvent(new CustomEvent("symphonia:workspaceInitialized", { detail: { repoKey } }));
      router.push(firstWorkspaceArtifactHref(slug, payload.privateWorkspace));
      onNavigate?.();
    } catch (err) {
      setSpecError(err instanceof Error ? err.message : "Could not set up private workspace");
      await loadSpecWorkspace().catch(() => setSpecWorkspace(null));
    } finally {
      setSpecPending(null);
    }
  };

  const archiveSpecArtifact = async (artifact: SpecArtifactSummary) => {
    const pendingKey = specArtifactPendingKey("delete", artifact);
    setSpecPending(pendingKey);
    try {
      const res = await fetch(
        `/api/repositories/${encodeURIComponent(repoKey)}/private-workspace/artifacts/${encodeURIComponent(
          artifact.type,
        )}/${encodeURIComponent(artifact.id)}`,
        {
          method: "PATCH",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            metadata: {
              status: "archived",
            },
          }),
        },
      );
      const payload = (await res.json()) as { artifact?: SpecArtifact; error?: string };
      if (!res.ok || !payload.artifact) {
        throw new Error(payload.error ?? "Could not move document to trash");
      }
      await loadSpecWorkspace();
      if (pathname === specArtifactHref(slug, artifact)) {
        router.push(`/r/${slug}`);
      }
    } catch {
      await loadSpecWorkspace().catch(() => undefined);
    } finally {
      setSpecPending(null);
    }
  };

  const workspaceInitialized = specWorkspace?.state.initialized === true;
  const repositoryRulesHref = `/r/${slug}/workflow`;

  return (
    <div className="space-y-3 text-[13px]">
      <div className="space-y-2">
        <ul className="border-l pl-1.5">
          <WorkspaceFileNode
            href={repositoryRulesHref}
            active={pathname === repositoryRulesHref}
            icon={<GitBranch className="h-3.5 w-3.5 shrink-0" />}
            title="Repository rules"
          />
        </ul>

        {WORKSPACE_GROUPS.map((group) => {
          const artifacts = workspaceInitialized
            ? group.sectionLabels.flatMap(
              (label) =>
                specWorkspace.sections
                  .find((section) => section.label === label)
                  ?.artifacts.filter((artifact) => artifact.status !== "archived") ?? [],
            )
            : [];

          return (
            <SpecArtifactSection
              key={group.label}
              label={group.label}
              artifacts={artifacts}
              pending={specPending}
              repoSlug={slug}
              currentPath={pathname}
              onArchive={archiveSpecArtifact}
            />
          );
        })}
      </div>

      {!workspaceInitialized && (
        <div className="rounded-md border border-dashed px-2 py-2">
          <p className="text-[11px] text-muted-foreground">Set up private workspace files for this repository.</p>
          <button
            id="setup-private-workspace-button"
            onClick={initializeSpecWorkspace}
            disabled={specPending === "initialize"}
            className="mt-2 rounded-md border bg-background px-2 py-1 text-[11px] hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
          >
            {specPending === "initialize" ? "Creating..." : "Set up private workspace"}
          </button>
          {specError && <p className="mt-2 text-[11px] text-amber-700 dark:text-amber-300">{specError}</p>}
        </div>
      )}
    </div>
  );
}

function SpecArtifactSection({
  label,
  artifacts,
  pending,
  repoSlug,
  currentPath,
  onArchive,
}: {
  label: string;
  artifacts: SpecWorkspaceSection["artifacts"];
  pending: string | null;
  repoSlug: string;
  currentPath: string;
  onArchive: (artifact: SpecArtifactSummary) => Promise<void>;
}) {
  const hasActiveArtifact = artifacts.some(
    (artifact) => currentPath === specArtifactHref(repoSlug, artifact),
  );
  const [open, setOpen] = useState(hasActiveArtifact);

  useEffect(() => {
    if (hasActiveArtifact) setOpen(true);
  }, [hasActiveArtifact]);

  if (artifacts.length === 0) return null;

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
      </div>
      {open && (
        <ul className="mt-1 border-l pl-1.5">
          {artifacts.map((artifact) => (
            <SpecArtifactNode
              key={`${artifact.type}:${artifact.id}`}
              artifact={artifact}
              repoSlug={repoSlug}
              active={currentPath === specArtifactHref(repoSlug, artifact)}
              pending={pending === specArtifactPendingKey("delete", artifact)}
              onArchive={onArchive}
            />
          ))}
        </ul>
      )}
    </section>
  );
}

function SpecArtifactNode({
  artifact,
  repoSlug,
  active,
  pending,
  onArchive,
}: {
  artifact: SpecArtifactSummary;
  repoSlug: string;
  active: boolean;
  pending: boolean;
  onArchive: (artifact: SpecArtifactSummary) => Promise<void>;
}) {
  const title = artifact.title || "Untitled";

  return (
    <WorkspaceFileNode
      href={specArtifactHref(repoSlug, artifact)}
      active={active}
      title={title}
      detail={EXPORT_STATUS_LABELS[artifact.exportStatus ?? "never_exported"] ?? "Private"}
      pending={pending}
      onArchive={() => void onArchive(artifact)}
    />
  );
}

function WorkspaceFileNode({
  href,
  active,
  title,
  detail,
  pending,
  icon,
  onArchive,
}: {
  href: string;
  active?: boolean;
  title: string;
  detail?: string;
  pending?: boolean;
  icon?: React.ReactNode;
  onArchive?: () => void;
}) {
  return (
    <li>
      <div
        className={cn(
          "group flex items-center gap-1 rounded-md pr-1 text-muted-foreground transition-colors hover:bg-sidebar-accent hover:text-foreground",
          active && "bg-sidebar-accent text-sidebar-accent-foreground",
        )}
      >
        <Link href={href} className="flex min-w-0 flex-1 items-center gap-1.5 px-1.5 py-1">
          {icon && <span className="text-muted-foreground">{icon}</span>}
          <span className="block truncate">
            {title || <span className="italic text-muted-foreground/70">Untitled</span>}
          </span>
          {detail && <span className="shrink-0 text-[10px] text-muted-foreground/70">{detail}</span>}
        </Link>
        {onArchive && (
          <button
            type="button"
            onClick={onArchive}
            disabled={pending}
            aria-label={`Move ${title} to trash`}
            title="Move to trash"
            className="grid h-6 w-6 shrink-0 place-items-center rounded-[8px] text-muted-foreground opacity-0 transition hover:bg-background/70 hover:text-foreground group-hover:opacity-100 focus:opacity-100 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <Trash2 className="h-3.5 w-3.5" />
          </button>
        )}
      </div>
    </li>
  );
}

function specArtifactPendingKey(
  action: "delete",
  artifact: Pick<SpecArtifactSummary, "type" | "id">,
) {
  return `spec-${action}:${artifact.type}:${artifact.id}`;
}

function specArtifactHref(
  slug: string,
  artifact: Pick<SpecArtifactSummary, "type" | "id">,
) {
  return `/r/${slug}/workspace/${encodeURIComponent(artifact.type)}/${encodeURIComponent(
    artifact.id,
  )}`;
}

function firstWorkspaceArtifactHref(slug: string, workspace: SpecWorkspacePayload) {
  const artifact = workspace.sections
    .flatMap((section) => section.artifacts)
    .find((item) => item.status !== "archived");

  return artifact ? specArtifactHref(slug, artifact) : `/r/${slug}`;
}
