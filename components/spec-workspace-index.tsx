"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import {
  ArrowRight,
  FileText,
  Landmark,
  ListChecks,
  Loader2,
  Milestone,
  Plus,
  ShieldCheck,
} from "lucide-react";
import type {
  SpecArtifactSummary,
  SpecArtifactType,
  SpecWorkspacePayload,
  SpecWorkspaceSection,
} from "@/lib/repository-model";
import { cn } from "@/lib/utils";

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

const SECTION_ICONS: Record<string, typeof FileText> = {
  Milestones: Milestone,
  Requirements: ListChecks,
  Plans: ShieldCheck,
  Decisions: Landmark,
  "Task briefs": FileText,
};

export function SpecWorkspaceIndex({ repoKey }: { repoKey: string }) {
  const repoSlug = repoKey.toLowerCase();
  const [workspace, setWorkspace] = useState<SpecWorkspacePayload | null>(null);
  const [loading, setLoading] = useState(true);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadWorkspace = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/spec-workspace`, {
        cache: "no-store",
      });
      const payload = (await res.json()) as {
        specWorkspace?: SpecWorkspacePayload;
        error?: string;
      };
      if (!res.ok || !payload.specWorkspace) {
        throw new Error(payload.error ?? "Could not load workspace");
      }
      setWorkspace(payload.specWorkspace);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not load workspace");
    } finally {
      setLoading(false);
    }
  }, [repoKey]);

  useEffect(() => {
    void loadWorkspace();
  }, [loadWorkspace]);

  const initialize = async () => {
    setPending(true);
    setError(null);
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
        throw new Error(payload.error ?? "Could not set up workspace");
      }
      setWorkspace(payload.specWorkspace);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not set up workspace");
    } finally {
      setPending(false);
    }
  };

  if (loading) {
    return (
      <div className="grid min-h-full place-items-center px-6 py-12 text-sm text-muted-foreground">
        <Loader2 className="mr-2 inline h-4 w-4 animate-spin" />
        Loading workspace
      </div>
    );
  }

  return (
    <div className="min-h-full bg-background">
      <header className="border-b px-4 py-5 sm:px-6">
        <div className="flex flex-wrap items-center gap-3">
          <div className="min-w-0 flex-1">
            <p className="text-[12px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
              Private workspace
            </p>
            <h1 className="mt-2 text-[30px] font-bold leading-none">
              Project memory
            </h1>
          </div>
          <Link
            href={`/r/${repoSlug}`}
            className="inline-flex h-9 items-center gap-2 rounded-[8px] bg-primary px-3 text-[13px] font-medium text-primary-foreground hover:bg-primary-hover"
          >
            <Plus className="h-4 w-4" />
            Create with Clarise
          </Link>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-4 py-6 sm:px-6">
        {error && (
          <div className="mb-5 rounded-[8px] border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-sm text-amber-300">
            {error}
          </div>
        )}

        {!workspace?.state.initialized ? (
          <div className="rounded-[10px] border bg-card p-6 shadow-[var(--elevation-card)]">
            <h2 className="text-xl font-semibold">Set up private workspace</h2>
            <p className="mt-2 max-w-2xl text-sm leading-6 text-muted-foreground">
              Clarise stores generated planning docs here as private Markdown artifacts.
            </p>
            <button
              onClick={initialize}
              disabled={pending}
              className="mt-5 inline-flex h-9 items-center gap-2 rounded-[8px] bg-primary px-3 text-[13px] font-medium text-primary-foreground hover:bg-primary-hover disabled:cursor-not-allowed disabled:opacity-50"
            >
              {pending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />}
              Set up workspace
            </button>
          </div>
        ) : (
          <div className="space-y-7">
            {workspace.sections.map((section) => (
              <ArtifactSection
                key={section.label}
                section={section}
                repoSlug={repoSlug}
              />
            ))}
            <Link
              href={`/r/${repoSlug}/workspace/milestone-loop`}
              className="inline-flex items-center gap-2 text-sm font-medium text-muted-foreground hover:text-foreground"
            >
              Milestone handoff
              <ArrowRight className="h-4 w-4" />
            </Link>
          </div>
        )}
      </main>
    </div>
  );
}

function ArtifactSection({
  section,
  repoSlug,
}: {
  section: SpecWorkspaceSection;
  repoSlug: string;
}) {
  const Icon = SECTION_ICONS[section.label] ?? FileText;

  return (
    <section>
      <div className="mb-3 flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <span className="grid h-8 w-8 place-items-center rounded-[8px] bg-card text-brand-accent-text">
            <Icon className="h-4 w-4" />
          </span>
          <h2 className="text-[18px] font-semibold">{section.label}</h2>
        </div>
        <span className="text-[12px] tabular-nums text-muted-foreground">
          {section.artifacts.length}
        </span>
      </div>

      {section.artifacts.length === 0 ? (
        <p className="rounded-[8px] border border-dashed px-3 py-3 text-sm text-muted-foreground">
          Empty
        </p>
      ) : (
        <ul className="grid gap-3 md:grid-cols-2">
          {section.artifacts.map((artifact) => (
            <li key={`${artifact.type}:${artifact.id}`}>
              <ArtifactLink artifact={artifact} repoSlug={repoSlug} />
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function ArtifactLink({
  artifact,
  repoSlug,
}: {
  artifact: SpecArtifactSummary;
  repoSlug: string;
}) {
  const isPrivate = artifact.metadata.private === true;

  return (
    <Link
      href={`/r/${repoSlug}/workspace/${encodeURIComponent(artifact.type)}/${encodeURIComponent(
        artifact.id,
      )}`}
      className={cn(
        "block rounded-[8px] border bg-card p-4 shadow-[var(--elevation-card)] transition hover:-translate-y-0.5 hover:shadow-[var(--elevation-card-hover)]",
      )}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-[12px] text-muted-foreground">{TYPE_LABELS[artifact.type]}</p>
          <h3 className="mt-1 truncate text-[16px] font-semibold">
            {artifact.title}
          </h3>
        </div>
        {isPrivate && (
          <span className="rounded-full border border-emerald-500/30 px-2 py-0.5 text-[10px] font-medium uppercase text-emerald-300">
            Private
          </span>
        )}
      </div>
      <div className="mt-4 flex items-center justify-between gap-3 text-[12px] text-muted-foreground">
        <span className="truncate font-mono">{artifact.id}</span>
        <ArrowRight className="h-3.5 w-3.5 shrink-0" />
      </div>
    </Link>
  );
}
