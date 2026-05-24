"use client";

import { useEffect, useMemo, useState } from "react";
import { AlertTriangle, Check, FileCode2 } from "lucide-react";
import type { WorkflowFile } from "@/lib/repository-model";
import { cn } from "@/lib/utils";

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

  for (const hook of hooks) {
    if (!seen.has(hook)) {
      errors.push({ line: 1, message: `Missing required hook "${hook}:"` });
    }
  }
  return errors;
}

export function WorkflowView({ repoKey }: { repoKey: string }) {
  const [workflow, setWorkflow] = useState<WorkflowFile | null>(null);
  const [body, setBody] = useState("");
  const [loading, setLoading] = useState(true);
  const [pending, setPending] = useState<string | null>(null);
  const [dirty, setDirty] = useState(false);
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
        if (!res.ok || !payload.workflow) throw new Error(payload.error ?? "Could not load WORKFLOW.md");
        return payload.workflow;
      })
      .then((next) => {
        if (cancelled) return;
        setWorkflow(next);
        setBody(next.body);
        setDirty(false);
      })
      .catch((err) => {
        if (!cancelled) setError(err instanceof Error ? err.message : "Could not load WORKFLOW.md");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [repoKey]);

  const errors = useMemo(() => validate(body), [body]);

  const createFromTemplate = async (template: string) => {
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
        throw new Error(payload.error ?? "Could not create WORKFLOW.md");
      }
      setWorkflow(payload.workflow);
      setBody(payload.workflow.body);
      setDirty(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not create WORKFLOW.md");
    } finally {
      setPending(null);
    }
  };

  const save = async () => {
    setPending("save");
    setError(null);
    try {
      const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/workflow`, {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ body }),
      });
      const payload = (await res.json()) as { workflow?: WorkflowFile; error?: string };
      if (!res.ok || !payload.workflow) throw new Error(payload.error ?? "Could not save WORKFLOW.md");
      setWorkflow(payload.workflow);
      setBody(payload.workflow.body);
      setDirty(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not save WORKFLOW.md");
    } finally {
      setPending(null);
    }
  };

  if (loading) {
    return (
      <div className="grid h-full place-items-center text-sm text-muted-foreground">
        Loading WORKFLOW.md...
      </div>
    );
  }

  if (!workflow) {
    return (
      <div className="grid h-full place-items-center text-sm text-muted-foreground">
        {error}
      </div>
    );
  }

  if (!workflow.exists) {
    return (
      <div className="flex h-full flex-col">
        <header className="border-b px-4 py-2.5 text-sm">
          <span className="font-semibold">Workflow</span>{" "}
          <span className="text-muted-foreground">/</span>{" "}
          <span className="font-mono text-[11px] text-muted-foreground">WORKFLOW.md</span>
        </header>
        {error && (
          <div className="border-b border-amber-500/30 bg-amber-500/10 px-4 py-2 text-xs text-amber-700 dark:text-amber-300">
            {error}
          </div>
        )}
        <div className="flex-1 overflow-y-auto">
          <div className="mx-auto max-w-2xl px-4 py-8">
            <h2 className="text-lg font-semibold">WORKFLOW.md is missing</h2>
            <p className="mt-1 text-sm text-muted-foreground">
              Choose a template to create the root workflow file for this repository.
            </p>
            <div className="mt-5 grid gap-2 sm:grid-cols-3">
              {workflow.templates.map((template) => (
                <button
                  key={template.id}
                  onClick={() => createFromTemplate(template.id)}
                  disabled={pending != null}
                  className="group rounded-lg border p-3 text-left transition-colors hover:border-foreground/20 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  <div className="flex items-center gap-1.5 text-sm font-medium">
                    <FileCode2 className="h-3.5 w-3.5 text-muted-foreground" />
                    {template.label}
                  </div>
                  <p className="mt-1 text-xs text-muted-foreground">{template.description}</p>
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col">
      <header className="flex flex-wrap items-center justify-between gap-2 border-b px-4 py-2.5">
        <div className="text-sm">
          <span className="font-semibold">Workflow</span>{" "}
          <span className="text-muted-foreground">/</span>{" "}
          <span className="font-mono text-[11px] text-muted-foreground">WORKFLOW.md</span>
        </div>
        <div className="flex items-center gap-2">
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
          <button
            onClick={save}
            disabled={!dirty || pending != null}
            className="rounded-md border px-2.5 py-1 text-xs hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
          >
            {pending === "save" ? "Saving..." : dirty ? "Save WORKFLOW.md" : "Saved"}
          </button>
        </div>
      </header>

      {error && (
        <div className="border-b border-amber-500/30 bg-amber-500/10 px-4 py-2 text-xs text-amber-700 dark:text-amber-300">
          {error}
        </div>
      )}

      <main className="flex-1 overflow-y-auto">
        <div className="mx-auto max-w-4xl px-4 py-5 sm:px-8">
          <textarea
            value={body}
            onChange={(event) => {
              setBody(event.target.value);
              setDirty(true);
            }}
            spellCheck={false}
            aria-label="WORKFLOW.md body"
            className="min-h-[60svh] w-full resize-y rounded-md border bg-background p-3 font-mono text-[13px] leading-6 outline-none focus:ring-2 focus:ring-ring"
          />

          <section className="mt-4 rounded-lg border bg-muted/30 p-3">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              Validation
            </h3>
            {errors.length === 0 ? (
              <p className="mt-1.5 text-xs text-muted-foreground">
                Workflow looks good. Coding Assistants will follow these hooks on the
                next task in {repoKey}.
              </p>
            ) : (
              <ul className="mt-2 space-y-1.5">
                {errors.map((item, index) => (
                  <li
                    key={`${item.line}-${index}`}
                    className="rounded-md border border-amber-500/30 bg-amber-500/5 p-2 text-[11px]"
                  >
                    <span className="font-mono text-amber-600 dark:text-amber-400">
                      L{item.line}
                    </span>{" "}
                    <span className="text-foreground">{item.message}</span>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>
      </main>
    </div>
  );
}
