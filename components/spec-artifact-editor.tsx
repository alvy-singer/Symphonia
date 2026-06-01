"use client";

import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import { GitPullRequest, Loader2 } from "lucide-react";
import { MarkdownEditor } from "@/components/editor/markdown-editor";
import type { DocPage } from "@/lib/docs-store";
import type {
  SpecArtifact,
  SpecArtifactStatus,
  SpecArtifactType,
} from "@/lib/repository-model";
import { cn } from "@/lib/utils";

const STATUS_LABELS: Record<SpecArtifactStatus, string> = {
  draft: "Draft",
  in_discussion: "In discussion",
  requirements_ready: "Requirements ready",
  plan_ready: "Plan ready",
  ready_for_approval: "Ready for approval",
  approved: "Approved",
  created: "Created",
  archived: "Archived",
};

const TYPE_LABELS: Record<SpecArtifactType, string> = {
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

type ArtifactEditorPatch = Partial<
  Pick<DocPage, "title" | "body" | "icon" | "cover" | "published">
>;

async function fetchArtifact(
  repoKey: string,
  type: string,
  id: string,
): Promise<SpecArtifact> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/private-workspace/artifacts/${encodeURIComponent(
      type,
    )}/${encodeURIComponent(id)}`,
    { cache: "no-store" },
  );
  const payload = (await res.json()) as { artifact?: SpecArtifact; error?: string };
  if (!res.ok || !payload.artifact) {
    throw new Error(payload.error ?? "Could not load document");
  }
  return payload.artifact;
}

async function saveArtifact(
  repoKey: string,
  artifact: SpecArtifact,
  payload: {
    title: string;
    status: SpecArtifactStatus;
    body: string;
    icon?: string;
    cover?: string;
  },
): Promise<SpecArtifact> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/private-workspace/artifacts/${encodeURIComponent(
      artifact.type,
    )}/${encodeURIComponent(artifact.id)}`,
    {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        body: payload.body,
        metadata: {
          title: payload.title,
          status: payload.status,
          icon: payload.icon ?? "",
          cover: payload.cover ?? "",
        },
      }),
    },
  );
  const data = (await res.json()) as { artifact?: SpecArtifact; error?: string };
  if (!res.ok || !data.artifact) {
    throw new Error(data.error ?? "Could not save document");
  }
  return data.artifact;
}

async function exportArtifact(repoKey: string, artifact: SpecArtifact): Promise<SpecArtifact> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/private-workspace/artifacts/${encodeURIComponent(
      artifact.type,
    )}/${encodeURIComponent(artifact.id)}/export`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ revision_id: artifact.latestRevisionId }),
    },
  );
  const data = (await res.json()) as { artifact?: SpecArtifact; error?: string };
  if (!res.ok || !data.artifact) {
    throw new Error(data.error ?? "Could not prepare export review");
  }
  return data.artifact;
}

async function canConfigureRepository(repoKey: string): Promise<boolean> {
  const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/access`, {
    cache: "no-store",
  });
  const payload = (await res.json()) as {
    permissions?: Record<string, boolean>;
  };
  return Boolean(res.ok && payload.permissions?.["repository.configure"]);
}

export function SpecArtifactEditor({
  repoKey,
  artifactType,
  artifactId,
}: {
  repoKey: string;
  artifactType: string;
  artifactId: string;
}) {
  const [artifact, setArtifact] = useState<SpecArtifact | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusPending, setStatusPending] = useState<SpecArtifactStatus | null>(null);
  const [canExport, setCanExport] = useState(false);
  const [exportPending, setExportPending] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    fetchArtifact(repoKey, artifactType, artifactId)
      .then((next) => {
        if (cancelled) return;
        setArtifact(next);
      })
      .catch((err) => {
        if (!cancelled) setError(err instanceof Error ? err.message : "Could not load document");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [repoKey, artifactType, artifactId]);

  useEffect(() => {
    let cancelled = false;
    canConfigureRepository(repoKey)
      .then((allowed) => {
        if (!cancelled) setCanExport(allowed);
      })
      .catch(() => {
        if (!cancelled) setCanExport(false);
      });
    return () => {
      cancelled = true;
    };
  }, [repoKey]);

  const editorPage = useMemo(() => {
    if (!artifact) return null;
    return artifactToPage(repoKey, artifact);
  }, [artifact, repoKey]);

  const persistPatch = useCallback(
    async (patch: ArtifactEditorPatch) => {
      if (!artifact) return;
      setError(null);
      const updated = await saveArtifact(repoKey, artifact, {
        title: (patch.title ?? artifact.title).trim() || "Untitled",
        status: statusForPatch(artifact.type, artifact.status, patch.published),
        body: patch.body ?? artifact.body,
        icon: patch.icon,
        cover: patch.cover,
      });
      setArtifact(updated);
      window.dispatchEvent(new CustomEvent("symphonia:specWorkspaceChanged", { detail: { repoKey } }));
    },
    [artifact, repoKey],
  );

  const prepareExport = useCallback(async () => {
    if (!artifact) return;
    setExportPending(true);
    setError(null);
    try {
      const updated = await exportArtifact(repoKey, artifact);
      setArtifact(updated);
      window.dispatchEvent(new CustomEvent("symphonia:specWorkspaceChanged", { detail: { repoKey } }));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not prepare export review");
    } finally {
      setExportPending(false);
    }
  }, [artifact, repoKey]);

  const updateStatus = useCallback(
    async (nextStatus: SpecArtifactStatus) => {
      if (!artifact) return;
      setStatusPending(nextStatus);
      setError(null);
      try {
        const updated = await saveArtifact(repoKey, artifact, {
          title: artifact.title,
          status: nextStatus,
          body: artifact.body,
          icon: stringMeta(artifact.metadata.icon),
          cover: stringMeta(artifact.metadata.cover),
        });
        setArtifact(updated);
        window.dispatchEvent(new CustomEvent("symphonia:specWorkspaceChanged", { detail: { repoKey } }));
      } catch (err) {
        setError(err instanceof Error ? err.message : "Could not save document");
      } finally {
        setStatusPending(null);
      }
    },
    [artifact, repoKey],
  );

  if (loading) {
    return (
      <div className="grid h-full place-items-center text-sm text-muted-foreground">
        Loading document...
      </div>
    );
  }

  if (!artifact || !editorPage) {
    return (
      <div className="grid h-full place-items-center text-sm text-muted-foreground">
        {error ?? "Document not found"}
      </div>
    );
  }

  return (
    <MarkdownEditor
      page={editorPage}
      onPersist={persistPatch}
      onPersistError={(err) => {
        setError(err instanceof Error ? err.message : "Could not save document");
      }}
      showPageActions
      stateRevision={artifact.status}
      actionsMenuContent={
        <StatusMenu
          status={artifact.status}
          pending={statusPending}
          onSelect={(nextStatus) => void updateStatus(nextStatus)}
        />
      }
      bodyPlaceholder={`Enter ${TYPE_LABELS[artifact.type].toLowerCase()} notes or type '/' for commands`}
      belowBodySlot={
        <div className="space-y-3">
          <ExportPanel
            artifact={artifact}
            canExport={canExport}
            pending={exportPending}
            onExport={() => void prepareExport()}
          />
          {error ? <Notice tone="warn">{error}</Notice> : null}
        </div>
      }
    />
  );
}

function ExportPanel({
  artifact,
  canExport,
  pending,
  onExport,
}: {
  artifact: SpecArtifact;
  canExport: boolean;
  pending: boolean;
  onExport: () => void;
}) {
  return (
    <div className="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-md border px-3 py-2 text-xs">
      <div className="min-w-0">
        <p className="font-medium">Export status: {exportStatusLabel(artifact.exportStatus)}</p>
        <p className="mt-1 truncate text-muted-foreground">
          {artifact.reviewBranch ?? artifact.legacyRepoPath ?? "Private artifact; no live repository sync."}
        </p>
      </div>
      {canExport && (
        <button
          type="button"
          onClick={onExport}
          disabled={pending}
          className="inline-flex h-8 items-center gap-2 rounded-[8px] border px-2.5 text-[12px] font-medium hover:bg-accent disabled:cursor-not-allowed disabled:opacity-50"
        >
          {pending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <GitPullRequest className="h-3.5 w-3.5" />}
          Prepare export review
        </button>
      )}
    </div>
  );
}

function StatusMenu({
  status,
  pending,
  onSelect,
}: {
  status: SpecArtifactStatus;
  pending: SpecArtifactStatus | null;
  onSelect: (status: SpecArtifactStatus) => void;
}) {
  return (
    <div>
      <div className="px-2 pb-1 pt-1 text-[11px] font-medium text-muted-foreground">
        Status
      </div>
      {(Object.keys(STATUS_LABELS) as SpecArtifactStatus[]).map((option) => (
        <button
          key={option}
          type="button"
          onClick={() => onSelect(option)}
          disabled={pending !== null || option === status}
          className={cn(
            "flex w-full items-center justify-between gap-2 rounded-md px-2 py-1.5 text-left text-[12px] transition-colors hover:bg-accent hover:text-foreground disabled:cursor-not-allowed disabled:opacity-50",
            option === status ? "text-foreground" : "text-muted-foreground",
          )}
        >
          <span className="truncate">{STATUS_LABELS[option]}</span>
          {option === status && <span className="text-[10px] text-muted-foreground">Current</span>}
          {pending === option && <span className="text-[10px] text-muted-foreground">Saving</span>}
        </button>
      ))}
    </div>
  );
}

function Notice({
  tone,
  children,
}: {
  tone: "ok" | "warn";
  children: ReactNode;
}) {
  return (
    <div
      className={cn(
        "mt-4 rounded-md border px-3 py-2 text-xs",
        tone === "ok"
          ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300"
          : "border-amber-500/30 bg-amber-500/10 text-amber-700 dark:text-amber-300",
      )}
    >
      {children}
    </div>
  );
}

function artifactToPage(repoKey: string, artifact: SpecArtifact): DocPage {
  const createdAt = toTimestamp(artifact.createdAt);
  const updatedAt = toTimestamp(artifact.updatedAt) || createdAt || Date.now();
  return {
    id: `spec:${artifact.type}:${artifact.id}`,
    repo: repoKey,
    category: "doc",
    path: artifact.path,
    title: artifact.title || "Untitled",
    body: artifact.body,
    icon: stringMeta(artifact.metadata.icon),
    cover: stringMeta(artifact.metadata.cover),
    published: isPublishedStatus(artifact.status),
    createdAt: createdAt || updatedAt,
    updatedAt,
  };
}

function statusForPatch(
  type: SpecArtifactType,
  current: SpecArtifactStatus,
  published: boolean | undefined,
): SpecArtifactStatus {
  if (published === false) return "draft";
  if (published === true && !isPublishedStatus(current)) return defaultPublishedStatus(type);
  return current;
}

function defaultPublishedStatus(type: SpecArtifactType): SpecArtifactStatus {
  switch (type) {
    case "discussion":
      return "in_discussion";
    case "requirements":
      return "requirements_ready";
    case "plan":
      return "plan_ready";
    case "task_proposal":
      return "ready_for_approval";
    case "task_brief":
    case "run_summary":
      return "created";
    case "codebase_map":
    case "codebase_conventions":
    case "codebase_architecture":
    case "milestone":
    case "decision":
      return "approved";
  }
}

function exportStatusLabel(status: SpecArtifact["exportStatus"]): string {
  switch (status) {
    case "linked":
      return "Linked";
    case "changed_since_export":
      return "Changed since export";
    case "pr_open":
      return "PR open";
    case "conflict":
      return "Conflict";
    case "unlinked":
      return "Unlinked";
    case "never_exported":
    default:
      return "Never exported";
  }
}

function isPublishedStatus(status: SpecArtifactStatus): boolean {
  return status !== "draft" && status !== "archived";
}

function stringMeta(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function toTimestamp(value: string | undefined): number | undefined {
  if (!value) return undefined;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}
