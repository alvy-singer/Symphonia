"use client";

import { useEffect, useMemo, useRef, useState } from "react";
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
  type ReviewNote,
  type CodingAssistantRun,
  type CodingAssistantRunEvent,
  type ServiceTask,
  type TaskEligibilityExplanation,
  type TaskLifecycleEvent,
} from "@/lib/task-model";
import { TaskStatusIcon } from "@/components/icons/task-status-icons";
import { PriorityIcon } from "@/components/icons/status-icons";
import { useClarise } from "@/components/clarise";
import { cn } from "@/lib/utils";
import {
  activeRunPollingTarget,
  isActiveRun,
  reviewHandoffForTask,
  runTimelineForTask,
} from "@/lib/harness-ui-model";

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

async function fetchEligibility(
  repoKey: string,
  taskKey: string,
): Promise<TaskEligibilityExplanation> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(
      taskKey,
    )}/harness/eligibility`,
    { cache: "no-store" },
  );
  const payload = (await res.json()) as {
    eligibility?: TaskEligibilityExplanation;
    error?: string;
  };
  if (!res.ok || !payload.eligibility) {
    throw new Error(payload.error ?? "Could not load task eligibility");
  }
  return payload.eligibility;
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

async function startCodingAssistantRun(
  repoKey: string,
  taskKey: string,
): Promise<ServiceTask> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(
      taskKey,
    )}/coding-assistant/runs`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({}),
    },
  );
  const data = (await res.json()) as { task?: ServiceTask; error?: string };
  if (!res.ok || !data.task) throw new Error(data.error ?? "Could not start Coding Assistant");
  return data.task;
}

async function fetchCodingAssistantRun(
  repoKey: string,
  taskKey: string,
  runId: string,
): Promise<CodingAssistantRun> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(
      taskKey,
    )}/coding-assistant/runs/${encodeURIComponent(runId)}`,
    { cache: "no-store" },
  );
  const data = (await res.json()) as { run?: CodingAssistantRun; error?: string };
  if (!res.ok || !data.run) throw new Error(data.error ?? "Could not load Coding Assistant run");
  return data.run;
}

async function fetchCodingAssistantRunEvents(
  repoKey: string,
  taskKey: string,
  runId: string,
): Promise<CodingAssistantRunEvent[]> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(
      taskKey,
    )}/coding-assistant/runs/${encodeURIComponent(runId)}/events`,
    { cache: "no-store" },
  );
  const data = (await res.json()) as {
    events?: CodingAssistantRunEvent[];
    error?: string;
  };
  if (!res.ok || !data.events) throw new Error(data.error ?? "Could not load run events");
  return data.events;
}

async function cancelCodingAssistantRun(
  repoKey: string,
  taskKey: string,
  runId: string,
): Promise<ServiceTask> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(
      taskKey,
    )}/coding-assistant/runs/${encodeURIComponent(runId)}/cancel`,
    { method: "POST" },
  );
  const data = (await res.json()) as { task?: ServiceTask; error?: string };
  if (!res.ok || !data.task) throw new Error(data.error ?? "Could not cancel Coding Assistant run");
  return data.task;
}

async function requestTaskChanges(
  repoKey: string,
  taskKey: string,
  feedback: string,
): Promise<{ task: ServiceTask; reviewNote: ReviewNote }> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(
      taskKey,
    )}/review/request-changes`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ feedback }),
    },
  );
  const data = (await res.json()) as {
    task?: ServiceTask;
    review_note?: ReviewNote;
    error?: string;
  };
  if (!res.ok || !data.task) throw new Error(data.error ?? "Could not request changes");
  return { task: data.task, reviewNote: data.review_note as ReviewNote };
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
      kind:
        | "coding_assistant_run"
        | "cancel_run"
        | "open_pull_request"
        | "refresh_pr"
        | "request_changes";
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
  const [eligibility, setEligibility] = useState<TaskEligibilityExplanation | null>(null);
  const [runEvents, setRunEvents] = useState<CodingAssistantRunEvent[]>([]);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [dirty, setDirty] = useState(false);
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [requestBoxOpen, setRequestBoxOpen] = useState(false);
  const [feedback, setFeedback] = useState("");
  const [feedbackError, setFeedbackError] = useState<string | null>(null);
  const bodyRef = useRef<HTMLTextAreaElement>(null);
  const clarise = useClarise();
  const taskKey = pageIdOrTaskKey;
  const repoSlug = repoKey.toLowerCase();

  useEffect(() => {
    let cancelled = false;
    setError(null);
    Promise.all([fetchTask(repoKey, taskKey), fetchEligibility(repoKey, taskKey).catch(() => null)])
      .then(([loaded, loadedEligibility]) => {
        if (cancelled) return;
        setTask(loaded);
        setEligibility(loadedEligibility);
        setRunEvents(loaded.run?.timeline ?? []);
        setTitle(loaded.title);
        setBody(loaded.body);
        setDirty(false);
        setNotice(null);
        setRequestBoxOpen(false);
        setFeedback("");
        setFeedbackError(null);
      })
      .catch((err: unknown) => {
        if (!cancelled) setError(err instanceof Error ? err.message : "Could not load task");
      });
    return () => {
      cancelled = true;
    };
  }, [repoKey, taskKey]);

  useEffect(() => {
    const activeRunId = activeRunPollingTarget(task);
    if (!task || !activeRunId) return;

    let cancelled = false;
    const refresh = async () => {
      try {
        const [updatedTask, updatedRun, updatedEvents] = await Promise.all([
          fetchTask(repoKey, task.key),
          fetchCodingAssistantRun(repoKey, task.key, activeRunId),
          fetchCodingAssistantRunEvents(repoKey, task.key, activeRunId).catch(() => []),
        ]);
        if (cancelled) return;
        const nextTask = { ...updatedTask, run: updatedRun };
        setTask(nextTask);
        setRunEvents(updatedEvents.length > 0 ? updatedEvents : (updatedRun.timeline ?? []));
        setTitle(nextTask.title);
        setBody(nextTask.body);
        setDirty(false);
      } catch {
        if (!cancelled) {
          const updatedTask = await fetchTask(repoKey, task.key);
          if (!cancelled) {
            setTask(updatedTask);
            setRunEvents(updatedTask.run?.timeline ?? []);
          }
        }
      }
    };

    const interval = window.setInterval(refresh, 2000);
    void refresh();
    return () => {
      cancelled = true;
      window.clearInterval(interval);
    };
  }, [repoKey, task?.key, task?.run?.id, task?.run?.state]);

  useEffect(() => {
    if (!task?.run?.id) {
      setRunEvents([]);
      return;
    }

    let cancelled = false;
    fetchCodingAssistantRunEvents(repoKey, task.key, task.run.id)
      .then((events) => {
        if (!cancelled) setRunEvents(events);
      })
      .catch(() => {
        if (!cancelled) setRunEvents(task.run?.timeline ?? []);
      });
    return () => {
      cancelled = true;
    };
  }, [repoKey, task?.key, task?.run?.id]);

  const pausedReason = pausedReasonLabel(task?.pausedReason);
  const activeRun = task?.run && isActiveRun(task.run) ? task.run : null;

  const save = async () => {
    if (!task) return;
    setPending("save");
    setError(null);
    try {
      const updated = await patchTask(repoKey, task.key, { title, body });
      setTask(updated);
      setRunEvents(updated.run?.timeline ?? runEvents);
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

    setPending(event);
    setError(null);
    try {
      const updated = await postTaskEvent(repoKey, task.key, event, params);
      setTask(updated);
      setEligibility(await fetchEligibility(repoKey, task.key).catch(() => eligibility));
      setRunEvents(updated.run?.timeline ?? runEvents);
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

    if (action.kind === "request_changes") {
      setRequestBoxOpen(true);
      setFeedbackError(null);
      return;
    }

    setPending(action.kind);
    setError(null);
    try {
      const updated =
        action.kind === "coding_assistant_run"
          ? await startCodingAssistantRun(repoKey, task.key)
          : action.kind === "cancel_run" && task.run
          ? await cancelCodingAssistantRun(repoKey, task.key, task.run.id)
          : action.kind === "open_pull_request"
          ? await openPullRequest(repoKey, task.key)
          : await refreshPullRequest(repoKey, task.key);
      setTask(updated);
      setEligibility(await fetchEligibility(repoKey, task.key).catch(() => eligibility));
      setRunEvents(updated.run?.timeline ?? runEvents);
      setTitle(updated.title);
      setBody(updated.body);
      setDirty(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not update task");
    } finally {
      setPending(null);
    }
  };

  const sendChanges = async () => {
    if (!task) return;
    const trimmed = feedback.trim();

    if (!trimmed) {
      setFeedbackError("Describe what Clarise should fix.");
      return;
    }

    setPending("request_changes");
    setError(null);
    setFeedbackError(null);
    setNotice(
      "Changes requested. Clarise turned your feedback into requested changes and is continuing the task.",
    );

    try {
      const { task: updated } = await requestTaskChanges(repoKey, task.key, trimmed);
      setTask(updated);
      setEligibility(await fetchEligibility(repoKey, task.key).catch(() => eligibility));
      setRunEvents(updated.run?.timeline ?? runEvents);
      setTitle(updated.title);
      setBody(updated.body);
      setDirty(false);
      setRequestBoxOpen(false);
      setFeedback("");
    } catch (err) {
      setNotice(null);
      setError(err instanceof Error ? err.message : "Could not request changes");
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

      {(pending === "coding_assistant_run" || activeRun) && (
        <div className="border-b bg-muted/40 px-4 py-2 text-xs text-muted-foreground">
              <span>Clarise is working on this task.</span>
          {activeRun?.currentStep && (
            <span className="ml-2 text-foreground">{activeRun.currentStep}</span>
          )}
        </div>
      )}

      {(pending === "request_changes" || notice) && (
        <div className="border-b bg-muted/40 px-4 py-2 text-xs text-muted-foreground">
          {notice ??
                "Changes requested. Clarise turned your feedback into requested changes and is continuing the task."}
        </div>
      )}

      {task.status === "paused" &&
        task.pausedReason === "waiting_for_user" &&
        task.pausedExplanation && (
          <div className="border-b bg-muted/40 px-4 py-2 text-xs text-muted-foreground">
            {task.pausedExplanation}
          </div>
        )}

      {eligibility && task.status === "todo" && (
        <div
          className={cn(
            "border-b px-4 py-2 text-xs",
            eligibility.eligible
              ? "bg-emerald-500/10 text-emerald-800 dark:text-emerald-200"
              : "bg-amber-500/10 text-amber-800 dark:text-amber-200",
          )}
        >
          Harness {eligibility.eligible ? "eligible" : "not eligible"}: {eligibility.reason}
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
              {task.status === "paused" && task.pausedReason === "run_failed" && (
                <>
                  <button
                    type="button"
                    onClick={() => bodyRef.current?.focus()}
                    disabled={pending != null}
                    className="inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    Edit task brief
                  </button>
                  <button
                    type="button"
                    onClick={() => clarise.open()}
                    disabled={pending != null}
                    className="inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    Ask Clarise what happened
                  </button>
                </>
              )}
              <button
                onClick={save}
                disabled={!dirty || pending != null || !title.trim()}
                className="ml-auto rounded-md border px-2.5 py-1 text-xs hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
              >
                {pending === "save" ? "Saving…" : dirty ? "Save Markdown" : "Saved"}
              </button>
            </div>

            {requestBoxOpen && (
              <div className="mt-4 rounded-md border bg-card p-3 shadow-sm">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <h2 className="text-sm font-medium">What should Clarise fix?</h2>
                    <p className="mt-1 text-xs text-muted-foreground">
                      Clarise will turn this into requested changes for the next run.
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() => {
                      setRequestBoxOpen(false);
                      setFeedback("");
                      setFeedbackError(null);
                    }}
                    disabled={pending != null}
                    className="rounded-md border px-2 py-1 text-xs text-muted-foreground hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    Cancel
                  </button>
                </div>
                <textarea
                  value={feedback}
                  onChange={(event) => {
                    setFeedback(event.target.value);
                    if (feedbackError) setFeedbackError(null);
                  }}
                  aria-label="Requested changes feedback"
                  className="mt-3 min-h-28 w-full resize-y rounded-md border bg-background px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-ring"
                  placeholder="The card is still too dense. Remove validation from the default card..."
                />
                {feedbackError && (
                  <p className="mt-2 text-xs text-amber-700 dark:text-amber-300">{feedbackError}</p>
                )}
                <div className="mt-3 flex justify-end">
                  <button
                    type="button"
                    onClick={sendChanges}
                    disabled={pending != null}
                    className="inline-flex items-center gap-1.5 rounded-md bg-primary px-2.5 py-1 text-xs text-primary-foreground hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    <RotateCcw className="h-3.5 w-3.5" />
                    {pending === "request_changes" ? "Sending…" : "Send changes"}
                  </button>
                </div>
              </div>
            )}

            <textarea
              ref={bodyRef}
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
          <TaskMeta task={task} eligibility={eligibility} runEvents={runEvents} />
        </aside>
      </div>
    </div>
  );
}

function TaskMeta({
  task,
  eligibility,
  runEvents,
}: {
  task: ServiceTask;
  eligibility: TaskEligibilityExplanation | null;
  runEvents: CodingAssistantRunEvent[];
}) {
  const handoff = reviewHandoffForTask(task);
  const timeline = runTimelineForTask(task, runEvents);

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
              <Section title="Clarise">
        <div className="inline-flex items-center gap-1.5">
          <Sparkles className="h-3 w-3 text-violet-500" />
          <span>{task.assistant || "Not assigned"}</span>
        </div>
      </Section>
      <Section title="Harness">
        {eligibility ? (
          <div className="space-y-2">
            <span
              className={cn(
                "inline-flex rounded-md border px-2 py-0.5",
                eligibility.eligible
                  ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
                  : "border-amber-500/30 bg-amber-500/10 text-amber-700 dark:text-amber-300",
              )}
            >
              {eligibility.eligible ? "Eligible" : "Not eligible"}
            </span>
            <p className="text-muted-foreground">{eligibility.reason}</p>
          </div>
        ) : (
          <span className="text-muted-foreground">No eligibility check loaded</span>
        )}
      </Section>
      {task.run && (
        <Section title="Run">
          <div className="space-y-1 text-muted-foreground">
            <p className="font-mono text-[11px]">{task.run.id}</p>
            {task.run.provider && <p>{task.run.provider}</p>}
            <p>{task.run.label ?? task.run.state}</p>
            {task.run.currentStep && <p>{task.run.currentStep}</p>}
            {task.run.message && <p>{task.run.message}</p>}
            {task.run.workspacePath && (
              <p className="break-all font-mono text-[11px]">{task.run.workspacePath}</p>
            )}
            {(task.run.codexThreadId || task.run.turnId) && (
              <p className="font-mono text-[11px]">
                {task.run.codexThreadId ?? "no-thread"} / {task.run.turnId ?? "no-turn"}
              </p>
            )}
            {task.run.reviewBranch && (
              <p className="break-all font-mono text-[11px]">{task.run.reviewBranch}</p>
            )}
            {task.run.curatedSummaryPath && (
              <p className="break-all font-mono text-[11px]">{task.run.curatedSummaryPath}</p>
            )}
          </div>
        </Section>
      )}
      {timeline.length > 0 && (
        <Section title="Run timeline">
          <ol className="space-y-2">
            {timeline.map((event, index) => (
              <li key={`${event.at ?? "event"}-${index}`} className="border-l pl-2">
                <p>{event.label ?? "Run event"}</p>
                <p className="font-mono text-[10px] text-muted-foreground">
                  {event.at ?? "time not recorded"}
                </p>
                {(event.threadId || event.turnId) && (
                  <p className="font-mono text-[10px] text-muted-foreground">
                    {event.threadId ?? "no-thread"} / {event.turnId ?? "no-turn"}
                  </p>
                )}
              </li>
            ))}
          </ol>
        </Section>
      )}
      <Section title="Review handoff">
        {handoff.summary ? (
          <div className="space-y-2">
            <p className="text-muted-foreground">{handoff.summary}</p>
            {handoff.files.length > 0 && (
              <ul className="space-y-1 font-mono text-[11px] text-muted-foreground">
                {handoff.files.map((file) => (
                  <li key={file}>{file}</li>
                ))}
              </ul>
            )}
            {handoff.branch && (
              <p className="font-mono text-[11px] text-muted-foreground">
                {handoff.branch}
              </p>
            )}
            {handoff.curatedSummaryPath && (
              <p className="break-all font-mono text-[11px] text-muted-foreground">
                {handoff.curatedSummaryPath}
              </p>
            )}
            {handoff.nextReviewAction && (
              <p className="text-[11px] text-muted-foreground">
                Next: {handoff.nextReviewAction}
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
          label: "Assign to Clarise",
          kind: "coding_assistant_run",
          icon: <Sparkles className="h-3.5 w-3.5" />,
          primary: true,
        },
      ];
    case "in_progress":
      return task.run && isActiveRun(task.run)
        ? [
            {
              label: "Cancel run",
              kind: "cancel_run",
              icon: <XCircle className="h-3.5 w-3.5" />,
            },
          ]
        : [];
    case "paused":
      if (task.pausedReason !== "run_failed") return [];
      return [
        {
          label: "Retry with Clarise",
          kind: "coding_assistant_run",
          icon: <RotateCcw className="h-3.5 w-3.5" />,
          primary: true,
        },
        {
          label: "Cancel task",
          kind: "event",
          event: "cancel",
          icon: <XCircle className="h-3.5 w-3.5" />,
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
          kind: "request_changes",
          icon: <RotateCcw className="h-3.5 w-3.5" />,
        },
      ];
    case "completed":
    case "canceled":
      return [];
  }
}
