"use client";

import { useEffect, useMemo, useState } from "react";
import { AlertTriangle, Check, FileCode2, Sparkles } from "lucide-react";
import { useDocs } from "@/lib/docs-store";
import { useDraftHost } from "@/components/draft-host";
import { MarkdownEditor } from "@/components/editor/markdown-editor";
import { cn } from "@/lib/utils";

const TEMPLATES: Record<string, { label: string; desc: string; body: string }> = {
  simple: {
    label: "Simple PR",
    desc: "Run → PR → human review.",
    body:
      "# WORKFLOW.md\n# Simple PR — assistant runs, opens a PR, human reviews on GitHub.\n\n" +
      "on_task_started:\n  - assign: codex\n  - require_pr: true\n\n" +
      "on_run_complete:\n  - status: in_review\n  - notify_assignees: true\n\n" +
      "on_pr_merged:\n  - status: completed\n",
  },
  reviewFirst: {
    label: "Review-first",
    desc: "Review the run summary in Symphonía before any PR.",
    body:
      "# WORKFLOW.md\n# Review-first — humans review the run summary in Symphonía before any PR.\n\n" +
      "on_task_started:\n  - assign: claude\n  - require_review: true\n\n" +
      "on_run_complete:\n  - status: in_review\n  - request_review_from: assignees\n\n" +
      "on_review_approved:\n  - open_pr: true\n\n" +
      "on_pr_merged:\n  - status: completed\n",
  },
  retry: {
    label: "Persistent retry",
    desc: "Auto-retry on validation failure.",
    body:
      "# WORKFLOW.md\n# Persistent retry — re-run on validation failures up to 3 times.\n\n" +
      "on_task_started:\n  - assign: cursor\n  - require_pr: true\n\n" +
      "on_run_failed:\n  - retry:\n      max: 3\n      backoff: exponential\n\n" +
      "on_run_complete:\n  - validate:\n      - tests\n      - typecheck\n      - lint\n\n" +
      "on_pr_merged:\n  - status: completed\n",
  },
};

interface ValidationError {
  line: number;
  message: string;
}

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
          message: `Unknown coding assistant "${v}". Use codex, claude, or cursor.`,
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

  for (const h of hooks) {
    if (!seen.has(h)) {
      errors.push({ line: 1, message: `Missing required hook "${h}:"` });
    }
  }
  return errors;
}

export function WorkflowView({ repoKey }: { repoKey: string }) {
  const { ensureWorkflow, updatePage, byPath } = useDocs();
  const { startDraft } = useDraftHost();
  const [pageId, setPageId] = useState<string | null>(null);

  // Resolve (or create) the WORKFLOW.md page once the store is hydrated.
  useEffect(() => {
    const existing = byPath(repoKey, "WORKFLOW.md");
    if (existing) {
      setPageId(existing.id);
    } else {
      const created = ensureWorkflow(repoKey);
      setPageId(created.id);
    }
  }, [repoKey, ensureWorkflow, byPath]);

  const page = pageId ? byPath(repoKey, "WORKFLOW.md") : undefined;
  const errors = useMemo(() => (page ? validate(page.body) : []), [page]);

  if (!page) {
    return (
      <div className="grid h-full place-items-center text-sm text-muted-foreground">
        Loading WORKFLOW.md…
      </div>
    );
  }

  // The "no body yet" empty state offers templates instead of a blank canvas.
  if (!page.body.trim()) {
    return (
      <div className="flex h-full flex-col">
        <header className="border-b px-4 py-2.5 text-sm">
          <span className="font-semibold">Workflow</span>{" "}
          <span className="text-muted-foreground">·</span>{" "}
          <span className="font-mono text-[11px] text-muted-foreground">WORKFLOW.md</span>
        </header>
        <div className="flex-1 overflow-y-auto">
          <div className="mx-auto max-w-2xl px-4 py-8">
            <h2 className="text-lg font-semibold">No workflow yet</h2>
            <p className="mt-1 text-sm text-muted-foreground">
              WORKFLOW.md tells Coding Assistants what to do on every task — who
              runs, when a PR opens, when a task is completed. Pick a template to
              start, or ask Clarise to draft one for you.
            </p>
            <div className="mt-5 grid gap-2 sm:grid-cols-3">
              {Object.entries(TEMPLATES).map(([k, t]) => (
                <button
                  key={k}
                  onClick={() => updatePage(page.id, { body: t.body })}
                  className="group rounded-lg border p-3 text-left hover:border-foreground/20 transition-colors"
                >
                  <div className="flex items-center gap-1.5 text-sm font-medium">
                    <FileCode2 className="h-3.5 w-3.5 text-muted-foreground" />
                    {t.label}
                  </div>
                  <p className="mt-1 text-xs text-muted-foreground">{t.desc}</p>
                </button>
              ))}
            </div>
            <button
              onClick={() =>
                startDraft(repoKey, "workflow", {
                  title: "WORKFLOW.md",
                  body: TEMPLATES.simple.body,
                })
              }
              className="mt-4 inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1 text-[12px] hover:bg-muted"
            >
              <Sparkles className="h-3.5 w-3.5 text-violet-500" /> Start as a draft instead
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col">
      <MarkdownEditor
        page={page}
        fixedTitle
        bodyPlaceholder="Define your workflow hooks. Markdown is preserved."
        rightToolbarSlot={
          <span
            className={cn(
              "inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px]",
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
        }
        belowBodySlot={
          <section className="mt-6 rounded-lg border bg-muted/30 p-3">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              Validation
            </h3>
            {errors.length === 0 ? (
              <p className="mt-1.5 text-xs text-muted-foreground">
                Workflow looks good. Coding Assistants will follow these hooks
                on the next task in {repoKey}.
              </p>
            ) : (
              <ul className="mt-2 space-y-1.5">
                {errors.map((e, i) => (
                  <li
                    key={i}
                    className="rounded-md border border-amber-500/30 bg-amber-500/5 p-2 text-[11px]"
                  >
                    <span className="font-mono text-amber-600 dark:text-amber-400">
                      L{e.line}
                    </span>{" "}
                    <span className="text-foreground">{e.message}</span>
                  </li>
                ))}
              </ul>
            )}
            <button
              onClick={() =>
                startDraft(repoKey, "workflow", {
                  title: "WORKFLOW.md",
                  body: TEMPLATES.reviewFirst.body,
                })
              }
              className="mt-3 inline-flex items-center gap-1.5 rounded-md border px-2 py-1 text-[11px] hover:bg-muted"
            >
              <Sparkles className="h-3 w-3 text-violet-500" /> Ask Clarise to fix this
            </button>
          </section>
        }
      />
    </div>
  );
}
