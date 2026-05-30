"use client";

import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import { AlertTriangle, Check, FileCode2 } from "lucide-react";
import { MarkdownEditor } from "@/components/editor/markdown-editor";
import type { WorkflowFile } from "@/lib/repository-model";
import type { DocPage } from "@/lib/docs-store";
import { cn } from "@/lib/utils";

interface ValidationError {
  line: number;
  message: string;
}

type WorkflowEditorPatch = Partial<
  Pick<DocPage, "title" | "body" | "icon" | "cover" | "published">
>;

const ruleTemplateCopy: Record<string, { label: string; description: string }> = {
  "review-first": {
    label: "Review before PR",
    description: "Codex writes a handoff first. You approve before opening a pull request.",
  },
  "simple-pr": {
    label: "Simple PR flow",
    description: "Codex prepares work for a pull request after running.",
  },
  "persistent-retry": {
    label: "Retry on failure",
    description: "Codex retries validation failures before handing work to review.",
  },
};

function validate(text: string): ValidationError[] {
  const errors: ValidationError[] = [];
  const lines = text.split("\n");
  const hooks = ["on_task_started", "on_run_complete", "on_pr_merged"];
  const seen = new Set<string>();

  lines.forEach((line, i) => {
    const trimmed = line.trim();
    const hookMatch = trimmed.match(/^([a-z_]+):$/);
    if (hookMatch) seen.add(hookMatch[1]);

    if (trimmed.startsWith("- assign:")) {
      const v = trimmed.replace("- assign:", "").trim();
      if (!["codex", "claude", "cursor"].includes(v)) {
        errors.push({
          line: i + 1,
          message: `Unknown AI assistant "${v}". Use a supported assistant configured by your team.`,
        });
      }
    }
    if (trimmed.startsWith("- status:")) {
      const v = trimmed.replace("- status:", "").trim();
      if (!["in_progress", "in_review", "completed", "paused"].includes(v)) {
        errors.push({ line: i + 1, message: `Unknown status "${v}".` });
      }
    }
  });

  for (const hook of hooks) {
    if (!seen.has(hook)) {
      errors.push({ line: 1, message: `Missing required hook "${hook}:"` });
    }
  }
  return errors;
}

export function WorkflowView({ repoKey }: { repoKey: string }) {
  const [workflow, setWorkflow] = useState<WorkflowFile | null>(null);
  const [draftBody, setDraftBody] = useState("");
  const [loading, setLoading] = useState(true);
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    fetch(`/api/repositories/${encodeURIComponent(repoKey)}/workflow`, {
      cache: "no-store",
    })
      .then(async (res) => {
        const payload = (await res.json()) as { workflow?: WorkflowFile; error?: string };
        if (!res.ok || !payload.workflow) {
          throw new Error(payload.error ?? "Could not load repository rules");
        }
        return payload.workflow;
      })
      .then((next) => {
        if (cancelled) return;
        setWorkflow(next);
        setDraftBody(next.body);
      })
      .catch((err) => {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : "Could not load repository rules");
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [repoKey]);

  const errors = useMemo(() => validate(draftBody), [draftBody]);

  const createFromTemplate = useCallback(
    async (template: string) => {
      setPending(template);
      setError(null);
      try {
        const res = await fetch(
          `/api/repositories/${encodeURIComponent(repoKey)}/workflow/from-template`,
          {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ template }),
          },
        );
        const payload = (await res.json()) as { workflow?: WorkflowFile; error?: string };
        if (!res.ok || !payload.workflow) {
          throw new Error(payload.error ?? "Could not create repository rules");
        }
        setWorkflow(payload.workflow);
        setDraftBody(payload.workflow.body);
      } catch (err) {
        setError(err instanceof Error ? err.message : "Could not create repository rules");
      } finally {
        setPending(null);
      }
    },
    [repoKey],
  );

  const persistPatch = useCallback(
    async (patch: WorkflowEditorPatch) => {
      const body = patch.body ?? draftBody;
      setError(null);
      const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/workflow`, {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ body }),
      });
      const payload = (await res.json()) as { workflow?: WorkflowFile; error?: string };
      if (!res.ok || !payload.workflow) {
        throw new Error(payload.error ?? "Could not save repository rules");
      }
      setWorkflow(payload.workflow);
      setDraftBody(payload.workflow.body);
    },
    [draftBody, repoKey],
  );

  const editorPage = useMemo(() => {
    if (!workflow) return null;
    return workflowToPage(repoKey, workflow);
  }, [repoKey, workflow]);

  if (loading) {
    return (
      <div className="grid h-full place-items-center text-sm text-muted-foreground">
        Loading repository rules...
      </div>
    );
  }

  if (!workflow || !editorPage) {
    return (
      <div className="grid h-full place-items-center text-sm text-muted-foreground">
        {error ?? "Repository rules not found"}
      </div>
    );
  }

  return (
    <MarkdownEditor
      page={editorPage}
      onPersist={persistPatch}
      onDraftChange={(patch) => {
        if (typeof patch.body === "string") setDraftBody(patch.body);
      }}
      onPersistError={(err) => {
        setError(err instanceof Error ? err.message : "Could not save repository rules");
      }}
      fixedTitle
      metadataControls={false}
      stateRevision={`${workflow.exists}:${workflow.body}`}
      rightToolbarSlot={
        !workflow.exists ? (
          <TemplateMenu
            templates={workflow.templates}
            pending={pending}
            onSelect={(template) => void createFromTemplate(template)}
          />
        ) : null
      }
      afterSaveStatusSlot={<ValidationBadge errors={errors} />}
      bodyPlaceholder="Define repository rules or type '/' for commands"
      belowBodySlot={<WorkflowNotices error={error} exists={workflow.exists} />}
    />
  );
}

function TemplateMenu({
  templates,
  pending,
  onSelect,
}: {
  templates: WorkflowFile["templates"];
  pending: string | null;
  onSelect: (template: string) => void;
}) {
  return (
    <div className="flex flex-wrap items-center justify-end gap-1.5">
      <span className="text-[11px] text-muted-foreground">Start from</span>
      {templates.map((template) => {
        const copy = ruleTemplateCopy[template.id] ?? template;
        return (
          <button
            key={template.id}
            type="button"
            onClick={() => onSelect(template.id)}
            disabled={pending != null}
            title={copy.description}
            className="inline-flex h-7 items-center gap-1.5 rounded-md border bg-background px-2 text-[11px] text-muted-foreground transition-colors hover:bg-muted hover:text-foreground disabled:cursor-not-allowed disabled:opacity-50"
          >
            <FileCode2 className="h-3.5 w-3.5" />
            {pending === template.id ? "Creating..." : copy.label}
          </button>
        );
      })}
    </div>
  );
}

function ValidationBadge({ errors }: { errors: ValidationError[] }) {
  return (
    <span
      className={cn(
        "inline-flex h-6 items-center gap-1 rounded-full border px-2 text-[11px]",
        errors.length === 0
          ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
          : "border-amber-500/30 bg-amber-500/10 text-amber-600 dark:text-amber-400",
      )}
    >
      {errors.length === 0 ? (
        <>
          <Check className="h-3 w-3" /> Valid
        </>
      ) : (
        <>
          <AlertTriangle className="h-3 w-3" /> {errors.length} issue
          {errors.length === 1 ? "" : "s"}
        </>
      )}
    </span>
  );
}

function WorkflowNotices({
  error,
  exists,
}: {
  error: string | null;
  exists: boolean;
}) {
  if (exists && !error) return null;

  return (
    <div className="mt-5 space-y-3">
      {!exists && (
        <Notice tone="warn">
          WORKFLOW.md has not been created yet. Type rules here or apply a template to create it.
        </Notice>
      )}
      {error && <Notice tone="warn">{error}</Notice>}
    </div>
  );
}

function Notice({
  tone,
  children,
}: {
  tone: "warn";
  children: ReactNode;
}) {
  return (
    <div className="rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-700 dark:text-amber-300">
      {children}
    </div>
  );
}

function workflowToPage(repoKey: string, workflow: WorkflowFile): DocPage {
  const now = Date.now();
  return {
    id: "workflow:WORKFLOW.md",
    repo: repoKey,
    category: "workflow",
    path: workflow.path,
    title: "Repository rules",
    body: workflow.body,
    createdAt: now,
    updatedAt: now,
  };
}
