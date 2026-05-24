"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  Check,
  ExternalLink,
  Github,
  GitPullRequest,
  RotateCcw,
  Sparkles,
  XCircle,
} from "lucide-react";
import { PRIORITY_LABELS } from "@/data/mock";
import {
  TASK_STATUS_LABELS,
  pausedReasonLabel,
  type ServiceTask,
  type TaskLifecycleEvent,
} from "@/lib/task-model";
import { TaskStatusIcon } from "@/components/icons/task-status-icons";
import { PriorityIcon } from "@/components/icons/status-icons";
import { cn } from "@/lib/utils";

interface Props {
  repoKey: string;
  pageIdOrTaskKey: string;
}

async function fetchTask(repoKey: string, taskKey: string): Promise<ServiceTask> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(taskKey)}`,
    { cache: "no-store" },
  );
  if (!res.ok) throw new Error("Task not found");
  const payload = (await res.json()) as { task: ServiceTask };
  return payload.task;
}

async function patchTask(
  repoKey: string,
  taskKey: string,
  payload: { title?: string; body?: string },
): Promise<ServiceTask> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(taskKey)}`,
    {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    },
  );
  if (!res.ok) throw new Error("Could not save task");
  const data = (await res.json()) as { task: ServiceTask };
  return data.task;
}

async function postTaskEvent(
  repoKey: string,
  taskKey: string,
  event: TaskLifecycleEvent,
  params?: Record<string, unknown>,
): Promise<ServiceTask> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(taskKey)}/events`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ event, params: params ?? {} }),
    },
  );
  if (!res.ok) throw new Error("Could not update task");
  const data = (await res.json()) as { task: ServiceTask };
  return data.task;
}

async function openPullRequest(repoKey: string, taskKey: string): Promise<ServiceTask> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(taskKey)}/open-pull-request`,
    { method: "POST" },
  );
  const data = (await res.json()) as { task?: ServiceTask; error?: string };
  if (!res.ok || !data.task) throw new Error(data.error ?? "Could not open pull request");
  return data.task;
}

async function refreshPullRequest(repoKey: string, taskKey: string): Promise<ServiceTask> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(taskKey)}/refresh-pr`,
    { method: "POST" },
  );
  const data = (await res.json()) as { task?: ServiceTask; error?: string };
  if (!res.ok || !data.task) throw new Error(data.error ?? "Could not refresh pull request");
  return data.task;
}

type TaskAction =
  | {
      label: string;
      kind: "event";
      event: TaskLifecycleEvent;
      icon: React.ReactNode;
      primary?: boolean;
      params?: Record<string, unknown>;
    }
  | {
      label: string;
      kind: "open_pull_request" | "refresh_pr";
      icon: React.ReactNode;
      primary?: boolean;
    }
  | {
      label: string;
      kind: "view_pr";
      icon: React.ReactNode;
      href: string;
    };

/**
 * Filesystem-backed task page.
 *
 * The body textarea edits the Markdown body from `symphonia/tasks/*.md`.
 * Lifecycle actions rewrite frontmatter in that same file through the service
 * API, proving the milestone-one Markdown roundtrip.
 */
export function TaskPage({ repoKey, pageIdOrTaskKey }: Props) {
  const [task, setTask] = useState<ServiceTask | null>(null);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [dirty, setDirty] = useState(false);
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const taskKey = pageIdOrTaskKey;
  const repoSlug = repoKey.toLowerCase();

  useEffect(() => {
    let cancelled = false;
    setError(null);
    fetchTask(repoKey, taskKey)
      .then((loaded) => {
        if (cancelled) return;
        setTask(loaded);
        setTitle(loaded.title);
        setBody(loaded.body);
        setDirty(false);
      })
      .catch((err: unknown) => {
        if (!cancelled) setError(err instanceof Error ? err.message : "Could not load task");
      });
    return () => {
      cancelled = true;
    };
  }, [repoKey, taskKey]);

  const pausedReason = pausedReasonLabel(task?.pausedReason);

  const save = async () => {
    if (!task) return;
    setPending("save");
    setError(null);
    try {
      const updated = await patchTask(repoKey, task.key, { title, body });
      setTask(updated);
      setTitle(updated.title);
      setBody(updated.body);
      setDirty(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not save task");
    } finally {
      setPending(null);
    }
  };

  const runEvent = async (
    event: TaskLifecycleEvent,
    params?: Record<string, unknown>,
  ) => {
    if (!task) return;
    let nextParams = params;
    if (event === "request_changes" && !nextParams?.feedback) {
      const feedback = window.prompt("What should the Coding Assistant fix?");
      if (!feedback) return;
      nextParams = { feedback };
    }

    setPending(event);
    setError(null);
    try {
      const updated = await postTaskEvent(repoKey, task.key, event, nextParams);
      setTask(updated);
      setTitle(updated.title);
      setBody(updated.body);
      setDirty(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not update task");
    } finally {
      setPending(null);
    }
  };

  const runAction = async (action: TaskAction) => {
    if (!task) return;

    if (action.kind === "event") {
      await runEvent(action.event, action.params);
      return;
    }

    if (action.kind === "view_pr") return;

    setPending(action.kind);
    setError(null);
    try {
      const updated =
        action.kind === "open_pull_request"
          ? await openPullRequest(repoKey, task.key)
          : await refreshPullRequest(repoKey, task.key);
      setTask(updated);
      setTitle(updated.title);
      setBody(updated.body);
      setDirty(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not update task");
    } finally {
      setPending(null);
    }
  };

  const availableActions = useMemo(() => (task ? actionsForTask(task) : []), [task]);

  if (!task && !error) {
    return (
      <div className="grid h-full place-items-center text-sm text-muted-foreground">
        Loading Markdown task…
      </div>
    );
  }

  if (!task) {
    return (
      <div className="grid h-full place-items-center text-sm text-muted-foreground">
        {error}
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
          Tasks
        </Link>
        <span className="text-muted-foreground">/</span>
        <span className="font-mono text-muted-foreground">{task.key}</span>
        <span className="ml-auto text-[11px] text-muted-foreground">
          Markdown source <span className="font-mono">{task.path}</span>
        </span>
      </header>

      {error && (
        <div className="border-b border-amber-500/30 bg-amber-500/10 px-4 py-2 text-xs text-amber-700 dark:text-amber-300">
          {error}
        </div>
      )}

      <div className="flex flex-1 min-h-0">
        <main className="min-w-0 flex-1 overflow-y-auto">
          <div className="mx-auto max-w-3xl px-4 py-5 sm:px-8">
            <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
              <span className="inline-flex items-center gap-1 rounded-full border px-2 py-0.5">
                <TaskStatusIcon status={task.status} />
                {TASK_STATUS_LABELS[task.status]}
              </span>
              {pausedReason && (
                <span className="rounded-full border border-orange-500/30 bg-orange-500/10 px-2 py-0.5 text-orange-600 dark:text-orange-400">
                  {pausedReason}
                </span>
              )}
              {task.githubPrState === "open" && (
                <span className="rounded-full border border-violet-500/30 bg-violet-500/10 px-2 py-0.5 text-violet-600 dark:text-violet-400">
                  PR Open
                </span>
              )}
            </div>

            <input
              value={title}
              onChange={(event) => {
                setTitle(event.target.value);
                setDirty(true);
              }}
              aria-label="Task title"
              className="mt-4 w-full bg-transparent text-3xl font-semibold tracking-tight outline-none placeholder:text-muted-foreground/40"
            />

            <div className="mt-3 flex flex-wrap items-center gap-2 border-y py-2">
              {availableActions.map((action) => (
                action.kind === "view_pr" ? (
                  <a
                    key={action.kind}
                    href={action.href}
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs hover:bg-muted"
                  >
                    {action.icon}
                    {action.label}
                  </a>
                ) : (
                  <button
                    key={action.kind === "event" ? action.event : action.kind}
                    onClick={() => runAction(action)}
                    disabled={pending != null}
                    className={cn(
                      "inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50",
                      action.primary && "bg-primary text-primary-foreground hover:opacity-90",
                    )}
                  >
                    {action.icon}
                    {pending === (action.kind === "event" ? action.event : action.kind)
                      ? "Working…"
                      : action.label}
                  </button>
                )
              ))}
              <button
                onClick={save}
                disabled={!dirty || pending != null || !title.trim()}
                className="ml-auto rounded-md border px-2.5 py-1 text-xs hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
              >
                {pending === "save" ? "Saving…" : dirty ? "Save Markdown" : "Saved"}
              </button>
            </div>

            <textarea
              value={body}
              onChange={(event) => {
                setBody(event.target.value);
                setDirty(true);
              }}
              spellCheck={false}
              aria-label="Task Markdown body"
              className="mt-4 min-h-[55svh] w-full resize-none bg-transparent font-mono text-[13px] leading-6 outline-none"
            />
          </div>
        </main>

        <aside className="hidden w-80 shrink-0 overflow-y-auto border-l bg-muted/20 p-3 text-xs md:block">
          <TaskMeta task={task} />
        </aside>
      </div>
    </div>
  );
}

function TaskMeta({ task }: { task: ServiceTask }) {
  return (
    <div className="space-y-4">
      <Section title="Status">
        <div className="flex items-center gap-1.5">
          <TaskStatusIcon status={task.status} />
          <span>{TASK_STATUS_LABELS[task.status]}</span>
        </div>
      </Section>
      {task.pausedExplanation && (
        <Section title="Paused reason">
          <p className="text-muted-foreground">{task.pausedExplanation}</p>
        </Section>
      )}
      <Section title="Priority">
        <div className="flex items-center gap-1.5">
          <PriorityIcon priority={task.priority} />
          <span>{PRIORITY_LABELS[task.priority]}</span>
        </div>
      </Section>
      <Section title="Project">
        <span className="text-muted-foreground">{task.project ?? "No project"}</span>
      </Section>
      <Section title="Coding Assistant">
        <div className="inline-flex items-center gap-1.5">
          <Sparkles className="h-3 w-3 text-violet-500" />
          <span>{task.assistant || "Not assigned"}</span>
        </div>
      </Section>
      <Section title="Review handoff">
        {task.reviewSummary ? (
          <div className="space-y-2">
            <p className="text-muted-foreground">{task.reviewSummary}</p>
            {task.filesChanged.length > 0 && (
              <ul className="space-y-1 font-mono text-[11px] text-muted-foreground">
                {task.filesChanged.map((file) => (
                  <li key={file}>{file}</li>
                ))}
              </ul>
            )}
            {task.nextReviewAction && (
              <p className="text-[11px] text-muted-foreground">
                Next: {task.nextReviewAction}
              </p>
            )}
          </div>
        ) : (
          <span className="text-muted-foreground">No handoff yet</span>
        )}
      </Section>
      <Section title="GitHub issue">
        {task.githubIssue ? (
          <a
            href={task.githubIssue}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1.5 rounded-md border bg-background px-2 py-1 hover:bg-muted"
          >
            <Github className="h-3 w-3" />
            <span>{task.githubIssueState ?? "linked"}</span>
            <ExternalLink className="h-3 w-3 text-muted-foreground" />
          </a>
        ) : (
          <span className="text-muted-foreground">Not linked</span>
        )}
      </Section>
      <Section title="Pull request">
        {task.githubPr ? (
          <a
            href={task.githubPr}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1.5 rounded-md border bg-background px-2 py-1 hover:bg-muted"
          >
            <GitPullRequest className="h-3 w-3" />
            <span>{task.githubPrState ?? "linked"}</span>
            <ExternalLink className="h-3 w-3 text-muted-foreground" />
          </a>
        ) : (
          <span className="text-muted-foreground">No PR</span>
        )}
      </Section>
      <Section title="File">
        <p className="break-all font-mono text-[11px] text-muted-foreground">{task.path}</p>
      </Section>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <h3 className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
        {title}
      </h3>
      <div className="mt-1">{children}</div>
    </div>
  );
}

function actionsForTask(task: ServiceTask): TaskAction[] {
  switch (task.status) {
    case "todo":
      return [
        {
          label: "Start work",
          kind: "event",
          event: "start",
          icon: <Sparkles className="h-3.5 w-3.5" />,
          primary: true,
        },
      ];
    case "in_progress":
      return [
        {
          label: "Submit for review",
          kind: "event",
          event: "submit_review",
          icon: <Check className="h-3.5 w-3.5" />,
          primary: true,
        },
        {
          label: "Fail run",
          kind: "event",
          event: "fail_run",
          icon: <XCircle className="h-3.5 w-3.5" />,
        },
      ];
    case "paused":
      return [
        {
          label: "Retry with Coding Assistant",
          kind: "event",
          event: "start",
          icon: <RotateCcw className="h-3.5 w-3.5" />,
          primary: true,
        },
      ];
    case "in_review":
      if (task.githubPrState === "open") {
        return [
          ...(task.githubPr
            ? [
                {
                  label: "View Pull Request",
                  kind: "view_pr" as const,
                  href: task.githubPr,
                  icon: <ExternalLink className="h-3.5 w-3.5" />,
                },
              ]
            : []),
          {
            label: "Refresh PR Status",
            kind: "refresh_pr",
            icon: <GitPullRequest className="h-3.5 w-3.5" />,
            primary: true,
          },
        ];
      }
      if (task.reviewApproved) {
        return [
          {
            label: "Open Pull Request",
            kind: "open_pull_request",
            icon: <GitPullRequest className="h-3.5 w-3.5" />,
            primary: true,
          },
        ];
      }
      return [
        {
          label: "Approve",
          kind: "event",
          event: "approve",
          icon: <Check className="h-3.5 w-3.5" />,
          primary: true,
        },
        {
          label: "Request changes",
          kind: "event",
          event: "request_changes",
          icon: <RotateCcw className="h-3.5 w-3.5" />,
        },
      ];
    case "completed":
    case "canceled":
      return [];
  }
}
