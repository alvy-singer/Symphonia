"use client";

import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  ExternalLink,
  GitPullRequest,
  Loader2,
  RefreshCw,
  Unlink,
  UploadCloud,
} from "lucide-react";
import { MarkdownEditor } from "@/components/editor/markdown-editor";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
} from "@/components/ui/dialog";
import type { DocPage } from "@/lib/docs-store";
import type { ExportPreview, WorkspaceArtifactExport } from "@/lib/export-model";
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

async function fetchExports(
  repoKey: string,
  artifact: Pick<SpecArtifact, "type" | "id">,
): Promise<WorkspaceArtifactExport[]> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/private-workspace/artifacts/${encodeURIComponent(
      artifact.type,
    )}/${encodeURIComponent(artifact.id)}/exports`,
    { cache: "no-store" },
  );
  const payload = (await res.json()) as { exports?: WorkspaceArtifactExport[]; error?: string };
  if (!res.ok) throw new Error(payload.error ?? "Could not load export state");
  return payload.exports ?? [];
}

async function previewGitHubExport(
  repoKey: string,
  artifact: SpecArtifact,
  payload: {
    revisionId: string;
    targetPath: string;
    baseBranch: string;
  },
): Promise<ExportPreview> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/private-workspace/artifacts/${encodeURIComponent(
      artifact.type,
    )}/${encodeURIComponent(artifact.id)}/export/github/preview`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    },
  );
  const data = (await res.json()) as { preview?: ExportPreview; error?: string };
  if (!res.ok || !data.preview) throw new Error(data.error ?? "Could not preview export");
  return data.preview;
}

async function openGitHubExportPr(
  repoKey: string,
  artifact: SpecArtifact,
  payload: {
    revisionId: string;
    targetPath: string;
    baseBranch: string;
    title: string;
    body: string;
  },
): Promise<{ artifact: SpecArtifact; export: WorkspaceArtifactExport }> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/private-workspace/artifacts/${encodeURIComponent(
      artifact.type,
    )}/${encodeURIComponent(artifact.id)}/export/github/open-pr`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    },
  );
  const data = (await res.json()) as {
    artifact?: SpecArtifact;
    export?: WorkspaceArtifactExport;
    error?: string;
  };
  if (!res.ok || !data.artifact || !data.export) {
    throw new Error(data.error ?? "Could not open export pull request");
  }
  return { artifact: data.artifact, export: data.export };
}

async function refreshGitHubExport(
  repoKey: string,
  artifact: SpecArtifact,
  exportId: string,
): Promise<{ artifact: SpecArtifact; export: WorkspaceArtifactExport }> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/private-workspace/artifacts/${encodeURIComponent(
      artifact.type,
    )}/${encodeURIComponent(artifact.id)}/exports/${encodeURIComponent(exportId)}/refresh`,
    { method: "POST" },
  );
  const data = (await res.json()) as {
    artifact?: SpecArtifact;
    export?: WorkspaceArtifactExport;
    error?: string;
  };
  if (!res.ok || !data.artifact || !data.export) {
    throw new Error(data.error ?? "Could not refresh export pull request");
  }
  return { artifact: data.artifact, export: data.export };
}

async function unlinkGitHubExport(
  repoKey: string,
  artifact: SpecArtifact,
  exportId: string,
): Promise<{ artifact: SpecArtifact; export: WorkspaceArtifactExport }> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/private-workspace/artifacts/${encodeURIComponent(
      artifact.type,
    )}/${encodeURIComponent(artifact.id)}/exports/${encodeURIComponent(exportId)}/unlink`,
    { method: "POST" },
  );
  const data = (await res.json()) as {
    artifact?: SpecArtifact;
    export?: WorkspaceArtifactExport;
    error?: string;
  };
  if (!res.ok || !data.artifact || !data.export) {
    throw new Error(data.error ?? "Could not unlink export");
  }
  return { artifact: data.artifact, export: data.export };
}

async function fetchRepositoryAccess(repoKey: string): Promise<Record<string, boolean>> {
  const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/access`, {
    cache: "no-store",
  });
  const payload = (await res.json()) as {
    permissions?: Record<string, boolean>;
  };
  return res.ok ? payload.permissions ?? {} : {};
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
  const [exports, setExports] = useState<WorkspaceArtifactExport[]>([]);
  const [canExport, setCanExport] = useState(false);
  const [canRefreshExport, setCanRefreshExport] = useState(false);
  const [exportPending, setExportPending] = useState(false);
  const [exportModalOpen, setExportModalOpen] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    fetchArtifact(repoKey, artifactType, artifactId)
      .then(async (next) => {
        if (cancelled) return;
        setArtifact(next);
        setExports(await fetchExports(repoKey, next).catch(() => []));
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
    fetchRepositoryAccess(repoKey)
      .then((nextPermissions) => {
        if (cancelled) return;
        setCanExport(Boolean(nextPermissions["private_workspace.export"]));
        setCanRefreshExport(Boolean(nextPermissions["pull_request.refresh"]));
      })
      .catch(() => {
        if (!cancelled) {
          setCanExport(false);
          setCanRefreshExport(false);
        }
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
    setExportModalOpen(true);
  }, [artifact]);

  const currentExport = useMemo(() => latestExport(exports), [exports]);

  const refreshExport = useCallback(async () => {
    if (!artifact || !currentExport?.id) return;
    setExportPending(true);
    setError(null);
    try {
      const result = await refreshGitHubExport(repoKey, artifact, currentExport.id);
      setArtifact(result.artifact);
      setExports((items) => replaceExport(items, result.export));
      window.dispatchEvent(new CustomEvent("symphonia:specWorkspaceChanged", { detail: { repoKey } }));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not refresh export pull request");
    } finally {
      setExportPending(false);
    }
  }, [artifact, currentExport, repoKey]);

  const unlinkExport = useCallback(async () => {
    if (!artifact || !currentExport?.id) return;
    setExportPending(true);
    setError(null);
    try {
      const result = await unlinkGitHubExport(repoKey, artifact, currentExport.id);
      setArtifact(result.artifact);
      setExports((items) => replaceExport(items, result.export));
      window.dispatchEvent(new CustomEvent("symphonia:specWorkspaceChanged", { detail: { repoKey } }));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not unlink export");
    } finally {
      setExportPending(false);
    }
  }, [artifact, currentExport, repoKey]);

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
    <>
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
              currentExport={currentExport}
              canExport={canExport}
              canRefresh={canRefreshExport}
              pending={exportPending}
              onExport={() => void prepareExport()}
              onRefresh={() => void refreshExport()}
              onUnlink={() => void unlinkExport()}
            />
            {error ? <Notice tone="warn">{error}</Notice> : null}
          </div>
        }
      />
      <ExportModal
        repoKey={repoKey}
        artifact={artifact}
        currentExport={currentExport}
        open={exportModalOpen}
        onOpenChange={setExportModalOpen}
        onCompleted={(result) => {
          setArtifact(result.artifact);
          setExports((items) => replaceExport(items, result.export));
          setExportModalOpen(false);
          window.dispatchEvent(new CustomEvent("symphonia:specWorkspaceChanged", { detail: { repoKey } }));
        }}
      />
    </>
  );
}

function ExportPanel({
  artifact,
  currentExport,
  canExport,
  canRefresh,
  pending,
  onExport,
  onRefresh,
  onUnlink,
}: {
  artifact: SpecArtifact;
  currentExport?: WorkspaceArtifactExport;
  canExport: boolean;
  canRefresh: boolean;
  pending: boolean;
  onExport: () => void;
  onRefresh: () => void;
  onUnlink: () => void;
}) {
  const primaryLabel = exportActionLabel(artifact.exportStatus);
  const prUrl = artifact.pullRequestUrl ?? artifact.githubPrUrl ?? currentExport?.pullRequestUrl;
  const hasOpenExportPr = currentExport?.pullRequestState === "open";

  return (
    <div className="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-md border px-3 py-2 text-xs">
      <div className="min-w-0">
        <p className="font-medium">Export status: {exportStatusLabel(artifact.exportStatus)}</p>
        <p className="mt-1 truncate text-muted-foreground">
          {artifact.exportTargetPath ??
            currentExport?.targetPath ??
            artifact.legacyRepoPath ??
            "Private artifact; no live repository sync."}
        </p>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        {prUrl && (
          <a
            href={prUrl}
            target="_blank"
            rel="noreferrer"
            className="inline-flex h-8 items-center gap-2 rounded-[8px] border px-2.5 text-[12px] font-medium hover:bg-accent"
          >
            <ExternalLink className="h-3.5 w-3.5" />
            View PR
          </a>
        )}
        {canRefresh && currentExport?.id && (
          <button
            type="button"
            onClick={onRefresh}
            disabled={pending}
            className="inline-flex h-8 items-center gap-2 rounded-[8px] border px-2.5 text-[12px] font-medium hover:bg-accent disabled:cursor-not-allowed disabled:opacity-50"
          >
            {pending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <RefreshCw className="h-3.5 w-3.5" />}
            Refresh
          </button>
        )}
        {canExport && currentExport?.id && artifact.exportStatus !== "unlinked" && (
          <button
            type="button"
            onClick={onUnlink}
            disabled={pending}
            className="inline-flex h-8 items-center gap-2 rounded-[8px] border px-2.5 text-[12px] font-medium hover:bg-accent disabled:cursor-not-allowed disabled:opacity-50"
          >
            <Unlink className="h-3.5 w-3.5" />
            Unlink
          </button>
        )}
        {canExport && artifact.exportStatus !== "pr_open" && !hasOpenExportPr && (
          <button
            type="button"
            onClick={onExport}
            disabled={pending}
            className="inline-flex h-8 items-center gap-2 rounded-[8px] border px-2.5 text-[12px] font-medium hover:bg-accent disabled:cursor-not-allowed disabled:opacity-50"
          >
            <GitPullRequest className="h-3.5 w-3.5" />
            {primaryLabel}
          </button>
        )}
      </div>
    </div>
  );
}

function ExportModal({
  repoKey,
  artifact,
  currentExport,
  open,
  onOpenChange,
  onCompleted,
}: {
  repoKey: string;
  artifact: SpecArtifact;
  currentExport?: WorkspaceArtifactExport;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onCompleted: (result: { artifact: SpecArtifact; export: WorkspaceArtifactExport }) => void;
}) {
  const [revisionId, setRevisionId] = useState(artifact.latestRevisionId ?? "");
  const [targetPath, setTargetPath] = useState(
    artifact.exportTargetPath ?? currentExport?.targetPath ?? defaultTargetPath(artifact),
  );
  const [baseBranch, setBaseBranch] = useState(artifact.baseBranch ?? currentExport?.baseBranch ?? "main");
  const [preview, setPreview] = useState<ExportPreview | null>(null);
  const [pending, setPending] = useState<"preview" | "open-pr" | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setRevisionId(artifact.latestRevisionId ?? "");
    setTargetPath(artifact.exportTargetPath ?? currentExport?.targetPath ?? defaultTargetPath(artifact));
    setBaseBranch(artifact.baseBranch ?? currentExport?.baseBranch ?? "main");
    setPreview(null);
    setError(null);
  }, [artifact, currentExport, open]);

  const revisions = artifact.metadata.revisions;
  const revisionOptions = Array.isArray(revisions) ? revisions : [];
  const isUpdate = artifact.exportStatus === "changed_since_export" || artifact.exportStatus === "linked";

  const buildPreview = async () => {
    setPending("preview");
    setError(null);
    try {
      const nextPreview = await previewGitHubExport(repoKey, artifact, {
        revisionId,
        targetPath,
        baseBranch,
      });
      setPreview(nextPreview);
    } catch (err) {
      setPreview(null);
      setError(err instanceof Error ? err.message : "Could not preview export");
    } finally {
      setPending(null);
    }
  };

  const openPr = async () => {
    setPending("open-pr");
    setError(null);
    try {
      const result = await openGitHubExportPr(repoKey, artifact, {
        revisionId,
        targetPath,
        baseBranch,
        title: `Export ${artifact.type}: ${artifact.title || artifact.id}`,
        body: "Adds a public snapshot of the private Symphonia artifact.",
      });
      onCompleted(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not open export pull request");
    } finally {
      setPending(null);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[86svh] w-[min(860px,calc(100vw-32px))] overflow-hidden p-0">
        <div className="grid max-h-[86svh] grid-rows-[auto_1fr_auto]">
          <div className="border-b px-5 py-4">
            <DialogTitle className="text-base font-semibold">Export to GitHub</DialogTitle>
            <DialogDescription className="mt-1 text-sm text-muted-foreground">
              {isUpdate
                ? "This will open a new PR updating the linked GitHub file. The private workspace remains the source of truth."
                : "This will publish the selected private artifact revision to GitHub through a pull request. Future private edits will not sync automatically."}
            </DialogDescription>
          </div>

          <div className="min-h-0 overflow-y-auto px-5 py-4">
            <div className="grid gap-4 md:grid-cols-[280px_1fr]">
              <div className="space-y-4">
                <label className="block text-[12px] font-medium">
                  Revision
                  <select
                    value={revisionId}
                    onChange={(event) => {
                      setRevisionId(event.target.value);
                      setPreview(null);
                    }}
                    className="mt-1 h-9 w-full rounded-md border bg-background px-2 text-sm"
                  >
                    {revisionOptions.length === 0 && artifact.latestRevisionId ? (
                      <option value={artifact.latestRevisionId}>{artifact.latestRevisionId}</option>
                    ) : null}
                    {revisionOptions.map((revision) => {
                      const id = revision && typeof revision === "object" ? String(revision.id ?? "") : "";
                      if (!id) return null;
                      return (
                        <option key={id} value={id}>
                          {id === artifact.latestRevisionId ? `${id} · current` : id}
                        </option>
                      );
                    })}
                  </select>
                </label>
                <label className="block text-[12px] font-medium">
                  Target path
                  <input
                    value={targetPath}
                    onChange={(event) => {
                      setTargetPath(event.target.value);
                      setPreview(null);
                    }}
                    className="mt-1 h-9 w-full rounded-md border bg-background px-2 font-mono text-sm"
                    placeholder="docs/symphonia/decisions/example.md"
                  />
                </label>
                <label className="block text-[12px] font-medium">
                  Base branch
                  <input
                    value={baseBranch}
                    onChange={(event) => {
                      setBaseBranch(event.target.value);
                      setPreview(null);
                    }}
                    className="mt-1 h-9 w-full rounded-md border bg-background px-2 text-sm"
                    placeholder="main"
                  />
                </label>
                <button
                  type="button"
                  onClick={() => void buildPreview()}
                  disabled={pending !== null || !revisionId || !targetPath || !baseBranch}
                  className="inline-flex h-9 w-full items-center justify-center gap-2 rounded-[8px] border px-3 text-[13px] font-medium hover:bg-accent disabled:cursor-not-allowed disabled:opacity-50"
                >
                  {pending === "preview" ? <Loader2 className="h-4 w-4 animate-spin" /> : <UploadCloud className="h-4 w-4" />}
                  Preview Markdown
                </button>
              </div>

              <div className="min-w-0">
                <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
                  <span className="text-[12px] font-medium">Markdown preview</span>
                  {preview ? (
                    <span
                      className={cn(
                        "inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px]",
                        preview.operation === "conflict"
                          ? "border-amber-500/40 text-amber-700 dark:text-amber-300"
                          : "border-emerald-500/40 text-emerald-700 dark:text-emerald-300",
                      )}
                    >
                      {preview.operation === "conflict" ? (
                        <AlertTriangle className="h-3 w-3" />
                      ) : (
                        <CheckCircle2 className="h-3 w-3" />
                      )}
                      {preview.operation}
                    </span>
                  ) : null}
                </div>
                <pre className="min-h-[320px] overflow-auto rounded-md border bg-muted/35 p-3 text-[12px] leading-5 text-foreground">
                  {preview?.markdownPreview ?? "Preview the export to inspect the exact Markdown that will be proposed in GitHub."}
                </pre>
                {preview?.warnings.length ? (
                  <Notice tone="warn">{preview.warnings.join(" ")}</Notice>
                ) : null}
                {error ? <Notice tone="warn">{error}</Notice> : null}
              </div>
            </div>
          </div>

          <div className="flex items-center justify-end gap-2 border-t px-5 py-3">
            <button
              type="button"
              onClick={() => onOpenChange(false)}
              className="h-9 rounded-[8px] border px-3 text-[13px] font-medium hover:bg-accent"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={() => void openPr()}
              disabled={pending !== null || !preview || preview.operation === "conflict"}
              className="inline-flex h-9 items-center gap-2 rounded-[8px] bg-primary px-3 text-[13px] font-medium text-primary-foreground hover:bg-primary-hover disabled:cursor-not-allowed disabled:opacity-50"
            >
              {pending === "open-pr" ? <Loader2 className="h-4 w-4 animate-spin" /> : <GitPullRequest className="h-4 w-4" />}
              Open PR
            </button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
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
      return "Linked to GitHub";
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

function exportActionLabel(status: SpecArtifact["exportStatus"]): string {
  switch (status) {
    case "changed_since_export":
    case "linked":
      return "Update GitHub copy";
    case "conflict":
    case "unlinked":
    case "never_exported":
    default:
      return "Export to GitHub";
  }
}

function latestExport(exports: WorkspaceArtifactExport[]): WorkspaceArtifactExport | undefined {
  return exports.at(-1);
}

function replaceExport(
  exports: WorkspaceArtifactExport[],
  nextExport: WorkspaceArtifactExport,
): WorkspaceArtifactExport[] {
  const filtered = exports.filter((item) => item.id !== nextExport.id);
  return [...filtered, nextExport];
}

function defaultTargetPath(artifact: SpecArtifact): string {
  const slug = slugText(artifact.title || artifact.id);
  switch (artifact.type) {
    case "codebase_map":
      return "docs/symphonia/codebase-map.md";
    case "codebase_conventions":
      return "docs/symphonia/codebase-conventions.md";
    case "milestone":
      return `docs/symphonia/milestones/${slug}.md`;
    case "plan":
      return `docs/symphonia/plans/${slug}.md`;
    case "decision":
      return `docs/symphonia/decisions/${slug}.md`;
    case "run_summary":
      return `docs/symphonia/run-summaries/${slug}.md`;
    default:
      return `docs/symphonia/${slug}.md`;
  }
}

function slugText(value: string): string {
  const slug = value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return slug || "artifact";
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
