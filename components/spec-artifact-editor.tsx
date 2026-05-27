"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { Save } from "lucide-react";
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
};

async function fetchArtifact(
  repoKey: string,
  type: string,
  id: string,
): Promise<SpecArtifact> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/spec-workspace/artifacts/${encodeURIComponent(
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
  payload: { title: string; status: SpecArtifactStatus; body: string },
): Promise<SpecArtifact> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/spec-workspace/artifacts/${encodeURIComponent(
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

export function SpecArtifactEditor({
  repoKey,
  artifactType,
  artifactId,
}: {
  repoKey: string;
  artifactType: string;
  artifactId: string;
}) {
  const repoSlug = repoKey.toLowerCase();
  const [artifact, setArtifact] = useState<SpecArtifact | null>(null);
  const [title, setTitle] = useState("");
  const [status, setStatus] = useState<SpecArtifactStatus>("draft");
  const [body, setBody] = useState("");
  const [dirty, setDirty] = useState(false);
  const [loading, setLoading] = useState(true);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    fetchArtifact(repoKey, artifactType, artifactId)
      .then((next) => {
        if (cancelled) return;
        setArtifact(next);
        setTitle(next.title);
        setStatus(next.status);
        setBody(next.body);
        setDirty(false);
        setNotice(null);
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

  const onSave = async () => {
    if (!artifact || !title.trim()) return;
    setPending(true);
    setError(null);
    try {
      const updated = await saveArtifact(repoKey, artifact, {
        title: title.trim(),
        status,
        body,
      });
      setArtifact(updated);
      setTitle(updated.title);
      setStatus(updated.status);
      setBody(updated.body);
      setDirty(false);
      setNotice("Document saved.");
      window.dispatchEvent(new CustomEvent("symphonia:specWorkspaceChanged", { detail: { repoKey } }));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not save document");
    } finally {
      setPending(false);
    }
  };

  if (loading) {
    return (
      <div className="grid h-full place-items-center text-sm text-muted-foreground">
        Loading document...
      </div>
    );
  }

  if (!artifact) {
    return (
      <div className="grid h-full place-items-center text-sm text-muted-foreground">
        {error ?? "Document not found"}
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col">
      <header className="flex flex-wrap items-center gap-2 border-b px-4 py-2 text-xs">
        <Link
          href={`/r/${repoSlug}/tasks`}
          className="text-muted-foreground hover:text-foreground"
        >
          Planning
        </Link>
        <span className="text-muted-foreground">/</span>
        <span className="text-muted-foreground">{TYPE_LABELS[artifact.type]}</span>
        <span className="text-muted-foreground">/</span>
        <span className="font-mono text-muted-foreground">{artifact.id}</span>
        <span className="ml-auto text-[11px] text-muted-foreground">Saved in repository</span>
      </header>

      {error && <Notice tone="warn">{error}</Notice>}
      {notice && !error && <Notice tone="ok">{notice}</Notice>}

      <main className="min-h-0 flex-1 overflow-y-auto">
        <div className="mx-auto max-w-4xl px-4 py-5 sm:px-8">
          <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
            <span className="rounded-full border px-2 py-0.5">{TYPE_LABELS[artifact.type]}</span>
            <span className="rounded-full border px-2 py-0.5">{STATUS_LABELS[status]}</span>
            {artifact.source && (
              <span className="rounded-full border px-2 py-0.5">Source: {artifact.source}</span>
            )}
          </div>

          <input
            value={title}
            onChange={(event) => {
              setTitle(event.target.value);
              setDirty(true);
            }}
            aria-label="Document title"
            className="mt-4 w-full bg-transparent text-3xl font-semibold tracking-tight outline-none placeholder:text-muted-foreground/40"
          />

          <div className="mt-3 flex flex-wrap items-center gap-2 border-y py-2">
            <label className="inline-flex items-center gap-2 text-xs text-muted-foreground">
              Status
              <select
                value={status}
                onChange={(event) => {
                  setStatus(event.target.value as SpecArtifactStatus);
                  setDirty(true);
                }}
                className="rounded-md border bg-background px-2 py-1 text-xs text-foreground"
              >
                {Object.entries(STATUS_LABELS).map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </label>
            <button
              onClick={onSave}
              disabled={!dirty || pending || !title.trim()}
              className={cn(
                "ml-auto inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs hover:bg-muted",
                "disabled:cursor-not-allowed disabled:opacity-50",
              )}
            >
              <Save className="h-3.5 w-3.5" />
              {pending ? "Saving..." : dirty ? "Save changes" : "Saved"}
            </button>
          </div>

          <textarea
            value={body}
            onChange={(event) => {
              setBody(event.target.value);
              setDirty(true);
            }}
            spellCheck={false}
            aria-label="Document body"
            className="mt-4 min-h-[58svh] w-full resize-y rounded-md border bg-background p-3 font-mono text-[13px] leading-6 outline-none focus:ring-2 focus:ring-ring"
          />
        </div>
      </main>
    </div>
  );
}

function Notice({
  tone,
  children,
}: {
  tone: "ok" | "warn";
  children: React.ReactNode;
}) {
  return (
    <div
      className={cn(
        "border-b px-4 py-2 text-xs",
        tone === "ok"
          ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300"
          : "border-amber-500/30 bg-amber-500/10 text-amber-700 dark:text-amber-300",
      )}
    >
      {children}
    </div>
  );
}
