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
import {
  TASK_STATUS_LABELS,
  pausedReasonLabel,
  type PullRequestRefreshResult,
  type ReviewNote,
  type CodingAssistantRun,
  type CodingAssistantRunEvent,
  type ServiceTask,
  type TaskEligibilityExplanation,
  type TaskLifecycleEvent,
} from "@/lib/task-model";
import { TaskStatusIcon } from "@/components/icons/task-status-icons";
import { useClarise } from "@/components/clarise";
import { cn } from "@/lib/utils";
import {
  activeRunPollingTarget,
  canOpenPullRequest,
  canRequestChanges,
  hasFailedRequiredValidation,
  isActiveRun,
  isReviewReady,
  prStateLabel,
  reviewHandoffForTask,
  reviewGateLabel,
  reviewGateState,
  reviewGateTone,
  runDisplayForTask,
  runOriginLabel,
  runTimelineForTask,
  safeReviewBranch,
  safeSummaryPath,
  taskOperationalBadge,
  terminalRunStateLabel,
  validationSummaryLabel,
  workspaceProviderLabel,
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

async function refreshPullRequest(
  repoKey: string,
  taskKey: string,
): Promise<{ task: ServiceTask; refreshResult: PullRequestRefreshResult }> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(taskKey)}/refresh-pr`,
    { method: "POST" },
  );
  const data = (await res.json()) as {
    task?: ServiceTask;
    refreshResult?: PullRequestRefreshResult;
    error?: string;
  };
  if (!res.ok || !data.task) throw new Error(data.error ?? "Could not refresh pull request");
  return {
    task: data.task,
    refreshResult: data.refreshResult ?? refreshResultForTask(data.task),
  };
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
  if (!res.ok || !data.task) throw new Error(data.error ?? "Could not start Codex");
  return data.task;
}

function refreshResultForTask(task: ServiceTask): PullRequestRefreshResult {
  const state =
    task.githubPrState === "open" ||
    task.githubPrState === "merged" ||
    task.githubPrState === "closed"
      ? task.githubPrState
      : "unknown";

  const message =
    state === "open"
      ? "Pull request is still open."
      : state === "merged"
        ? "Pull request was merged. Task completed."
        : state === "closed"
          ? "Pull request was closed without merge. Task remains in review."
          : "Could not confirm pull request state.";

  return {
    state,
    message,
    refreshedAt: new Date().toISOString(),
  };
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
  if (!res.ok || !data.run) throw new Error(data.error ?? "Could not load Codex run");
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
  if (!res.ok || !data.task) throw new Error(data.error ?? "Could not cancel Codex run");
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

function parseRunProgress(message: MessageEvent): CodingAssistantRunEvent | null {
  try {
    const data = JSON.parse(message.data) as CodingAssistantRunEvent;
    return {
      ...data,
      id: message.lastEventId || data.id,
      event: "run-progress",
      at: data.updatedAt,
      label: data.displayStep,
    };
  } catch {
    return null;
  }
}

function appendRunProgress(
  events: CodingAssistantRunEvent[],
  progress: CodingAssistantRunEvent,
): CodingAssistantRunEvent[] {
  if (progress.id && events.some((event) => event.id === progress.id)) return events;

  return [
    ...events,
    {
      id: progress.id,
      event: "run-progress",
      at: progress.updatedAt ?? progress.at,
      label: progress.displayStep ?? progress.label,
      runId: progress.runId,
      taskKey: progress.taskKey,
      state: progress.state,
      displayStep: progress.displayStep,
      displayMessage: progress.displayMessage,
      reviewBranch: progress.reviewBranch,
      curatedSummaryPath: progress.curatedSummaryPath,
      updatedAt: progress.updatedAt,
    },
  ];
}

function isTerminalRunState(state?: string): boolean {
  return state === "completed" || state === "failed" || state === "canceled";
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
  const [openPrConfirmOpen, setOpenPrConfirmOpen] = useState(false);
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
        setOpenPrConfirmOpen(false);
        setFeedback("");
        setFeedbackError(null);
      })
      .catch((err: unknown) => {
        if (!cancelled) setError(safeMessage(err, "Could not load task"));
      });
    return () => {
      cancelled = true;
    };
  }, [repoKey, taskKey]);

  useEffect(() => {
    const activeRunId = activeRunPollingTarget(task);
    if (!task || !activeRunId) return;

    let cancelled = false;
    let source: EventSource | null = null;
    let interval: number | null = null;

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

    const startPolling = () => {
      if (interval != null || cancelled) return;
      interval = window.setInterval(refresh, 2000);
      void refresh();
    };

    if ("EventSource" in window) {
      source = new EventSource(
        `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(
          task.key,
        )}/runs/${encodeURIComponent(activeRunId)}/events`,
      );

      source.addEventListener("run-progress", (message) => {
        if (cancelled) return;

        const progress = parseRunProgress(message);
        if (!progress) return;

        setRunEvents((events) => appendRunProgress(events, progress));
        setTask((current) => {
          if (!current?.run || current.run.id !== activeRunId) return current;

          return {
            ...current,
            run: {
              ...current.run,
              state: progress.state ?? current.run.state,
              displayStep: progress.displayStep ?? current.run.displayStep,
              displayMessage: progress.displayMessage ?? current.run.displayMessage,
              reviewBranch: progress.reviewBranch ?? current.run.reviewBranch,
              curatedSummaryPath:
                progress.curatedSummaryPath ?? current.run.curatedSummaryPath,
            },
          };
        });

        if (isTerminalRunState(progress.state)) {
          source?.close();
          void refresh();
        }
      });

      source.onerror = () => {
        source?.close();
        startPolling();
      };
    } else {
      startPolling();
    }

    return () => {
      cancelled = true;
      source?.close();
      if (interval != null) window.clearInterval(interval);
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
  const activeRunDisplay = runDisplayForTask({ run: activeRun });

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
      setError(safeMessage(err, "Could not save task"));
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
      setError(safeMessage(err, "Could not update task"));
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
      if (!canRequestChanges(task)) {
        setError(
          "This task already has an open pull request. Request changes on the PR, or close the PR before continuing in Symphonia.",
        );
        return;
      }
      setRequestBoxOpen(true);
      setOpenPrConfirmOpen(false);
      setFeedbackError(null);
      return;
    }

    if (action.kind === "open_pull_request") {
      if (!canOpenPullRequest(task)) {
        setError("Approve the handoff before opening a pull request.");
        return;
      }
      setOpenPrConfirmOpen(true);
      setRequestBoxOpen(false);
      return;
    }

    setPending(action.kind);
    setError(null);
    try {
      let updated: ServiceTask;

      if (action.kind === "coding_assistant_run") {
        updated = await startCodingAssistantRun(repoKey, task.key);
      } else if (action.kind === "cancel_run" && task.run) {
        updated = await cancelCodingAssistantRun(repoKey, task.key, task.run.id);
      } else {
        const result = await refreshPullRequest(repoKey, task.key);
        updated = result.task;
        setNotice(result.refreshResult.message);
      }

      if (action.kind === "coding_assistant_run") {
        window.dispatchEvent(
          new CustomEvent("symphonia:codexRunStarted", {
            detail: { repoKey, taskKey: task.key },
          }),
        );
      }
      setTask(updated);
      setEligibility(await fetchEligibility(repoKey, task.key).catch(() => eligibility));
      setRunEvents(updated.run?.timeline ?? runEvents);
      setTitle(updated.title);
      setBody(updated.body);
      setDirty(false);
    } catch (err) {
      setError(safeMessage(err, "Could not update task"));
    } finally {
      setPending(null);
    }
  };

  const sendChanges = async () => {
    if (!task) return;
    if (!canRequestChanges(task)) {
      setError(
        "This task already has an open pull request. Request changes on the PR, or close the PR before continuing in Symphonia.",
      );
      return;
    }

    const trimmed = feedback.trim();

    if (!trimmed) {
      setFeedbackError("Describe what Codex should fix.");
      return;
    }

    setPending("request_changes");
    setError(null);
    setFeedbackError(null);
    setNotice(
      "Changes requested. Codex is continuing the task.",
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
      setError(safeMessage(err, "Could not request changes"));
    } finally {
      setPending(null);
    }
  };

  const confirmOpenPullRequest = async () => {
    if (!task) return;

    if (!canOpenPullRequest(task)) {
      setError("Approve the handoff before opening a pull request.");
      setOpenPrConfirmOpen(false);
      return;
    }

    setPending("open_pull_request");
    setError(null);
    setNotice(null);

    try {
      const updated = await openPullRequest(repoKey, task.key);
      setTask(updated);
      setEligibility(await fetchEligibility(repoKey, task.key).catch(() => eligibility));
      setRunEvents(updated.run?.timeline ?? runEvents);
      setTitle(updated.title);
      setBody(updated.body);
      setDirty(false);
      setOpenPrConfirmOpen(false);
      setNotice("Pull request opened. Symphonia will not merge it automatically.");
    } catch (err) {
      setError(safeMessage(err, "Could not open pull request"));
    } finally {
      setPending(null);
    }
  };

  const availableActions = useMemo(() => (task ? actionsForTask(task) : []), [task]);

  if (!task && !error) {
    return (
      <div className="grid h-full place-items-center text-sm text-muted-foreground">
        Loading task…
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
        <span className="ml-auto text-[11px] text-muted-foreground">Saved in repository</span>
      </header>

      {error && (
        <div className="border-b border-amber-500/30 bg-amber-500/10 px-4 py-2 text-xs text-amber-700 dark:text-amber-300">
          {error}
        </div>
      )}

      {(pending === "coding_assistant_run" || activeRun) && (
        <div className="border-b bg-muted/40 px-4 py-2 text-xs text-muted-foreground">
          <span>Codex is working</span>
          {activeRunDisplay.step && (
            <span className="ml-2 text-foreground">- {activeRunDisplay.step}</span>
          )}
        </div>
      )}

      {(pending === "request_changes" || notice) && (
        <div className="border-b bg-muted/40 px-4 py-2 text-xs text-muted-foreground">
          {notice ?? "Changes requested. Codex is continuing the task."}
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
          Automation {eligibility.eligible ? "eligible" : "not eligible"}: {eligibility.reason}
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
                    id={action.kind === "coding_assistant_run" ? "ask-codex-button" : undefined}
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
                {pending === "save" ? "Saving…" : dirty ? "Save changes" : "Saved"}
              </button>
            </div>

            {openPrConfirmOpen && (
              <OpenPullRequestConfirmation
                task={task}
                pending={pending === "open_pull_request"}
                onCancel={() => setOpenPrConfirmOpen(false)}
                onConfirm={confirmOpenPullRequest}
              />
            )}

            {requestBoxOpen && (
              <div className="mt-4 rounded-md border bg-card p-3 shadow-sm">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <h2 className="text-sm font-medium">What should Codex fix?</h2>
                    <p className="mt-1 text-xs text-muted-foreground">
                      Codex will continue from this review note.
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
              aria-label="Task details"
              className="mt-4 min-h-[55svh] w-full resize-none bg-transparent font-mono text-[13px] leading-6 outline-none"
            />
          </div>
        </main>

        <aside className="hidden w-80 shrink-0 overflow-y-auto border-l bg-muted/20 p-3 text-xs md:block">
          <TaskMeta
            repoKey={repoKey}
            task={task}
            eligibility={eligibility}
            runEvents={runEvents}
            actions={availableActions}
            pending={pending}
            onAction={runAction}
          />
        </aside>
      </div>
    </div>
  );
}

function TaskMeta({
  repoKey,
  task,
  eligibility,
  runEvents,
  actions,
  pending,
  onAction,
}: {
  repoKey: string;
  task: ServiceTask;
  eligibility: TaskEligibilityExplanation | null;
  runEvents: CodingAssistantRunEvent[];
  actions: TaskAction[];
  pending: string | null;
  onAction: (action: TaskAction) => void;
}) {
  const handoff = reviewHandoffForTask(task);
  const timeline = runTimelineForTask(task, runEvents);
  const runDisplay = runDisplayForTask(task);
  const run = task.run ?? null;
  const terminalState = terminalRunStateLabel(run);
  const reviewReady = isReviewReady(task);
  const runBranch = safeReviewBranch(run?.reviewBranch ?? task.handoff?.headBranch);
  const runSummaryPath = safeSummaryPath(run?.curatedSummaryPath ?? task.handoff?.curatedSummaryPath);
  const allowedReason = run?.eligibilityReason ?? eligibility?.reason;
  const recoveryMessage = recoveryMessageForTask(task);
  const gateState = reviewGateState(task);
  const operationalBadge = taskOperationalBadge(task);
  const reviewFocused = task.status === "in_review" && Boolean(task.handoff);

  useEffect(() => {
    if (!handoff.summary) return;
    window.dispatchEvent(
      new CustomEvent("symphonia:taskHandoffViewed", {
        detail: { repoKey, taskKey: task.key },
      }),
    );
  }, [handoff.summary, repoKey, task.key]);

  const runPanel = (
    <Panel title="Coding Assistant Run">
      <Section title="Task state">
        <div className="flex items-center gap-1.5">
          <TaskStatusIcon status={task.status} />
          <span>{TASK_STATUS_LABELS[task.status]}</span>
        </div>
      </Section>
      <Section title="Origin">
        <div className="inline-flex items-center gap-1.5">
          <Sparkles className="h-3 w-3 text-violet-500" />
          <span>{run ? runOriginLabel(run) : "Not assigned"}</span>
        </div>
      </Section>
      {run && (
        <Section title="Workspace">
          <span className="text-muted-foreground">{workspaceProviderLabel(run)}</span>
        </Section>
      )}
      <Section title="Why it started">
        <p className="text-muted-foreground">
          {allowedReason ?? "No run eligibility reason recorded"}
        </p>
      </Section>
      <Section title="Current state">
        <div className="space-y-1 text-muted-foreground">
          <p>{terminalState ?? run?.label ?? run?.state ?? "No run yet"}</p>
          {runDisplay.step && <p>{runDisplay.step}</p>}
          {runDisplay.message && <p>{runDisplay.message}</p>}
        </div>
      </Section>
      {operationalBadge && (
        <Section title="Harness state">
          <div className="space-y-1">
            <span
              className={cn(
                "inline-flex rounded-md border px-2 py-0.5",
                operationalBadge.tone === "warning"
                  ? "border-amber-500/30 bg-amber-500/10 text-amber-700 dark:text-amber-300"
                  : operationalBadge.tone === "ready"
                    ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
                    : "text-muted-foreground",
              )}
            >
              {operationalBadge.label}
            </span>
            {operationalBadge.reason && (
              <p className="text-muted-foreground">{operationalBadge.reason}</p>
            )}
          </div>
        </Section>
      )}
      {recoveryMessage && (
        <Section title="Recovery">
          <p className="text-muted-foreground">{recoveryMessage}</p>
        </Section>
      )}
      {runBranch && (
        <Section title="Review branch">
          <p className="font-mono text-[11px] text-muted-foreground">{runBranch}</p>
        </Section>
      )}
      {runSummaryPath && (
        <Section title="Curated summary">
          <p className="font-mono text-[11px] text-muted-foreground">{runSummaryPath}</p>
        </Section>
      )}
      {timeline.length > 0 && (
        <Section title="Public timeline">
          <ol className="space-y-2">
            {timeline.map((event, index) => (
              <li key={`${event.at ?? "event"}-${index}`} className="border-l pl-2">
                <p>{event.label ?? "Run event"}</p>
                <p className="font-mono text-[10px] text-muted-foreground">
                  {event.at ?? "time not recorded"}
                </p>
              </li>
            ))}
          </ol>
        </Section>
      )}
    </Panel>
  );

  const handoffPanel = (
    <Panel id={handoff.summary ? "review-handoff-panel" : undefined} title="Review Handoff">
      <Section title="State">
        <span
          className={cn(
            "inline-flex rounded-md border px-2 py-0.5",
            reviewGateTone(gateState) === "ready"
              ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
              : reviewGateTone(gateState) === "warning"
                ? "border-amber-500/30 bg-amber-500/10 text-amber-700 dark:text-amber-300"
                : reviewReady
                  ? "border-sky-500/30 bg-sky-500/10 text-sky-600 dark:text-sky-400"
                  : "text-muted-foreground",
          )}
        >
          {reviewReady ? reviewGateLabel(task) : "No handoff yet"}
        </span>
      </Section>
      <Section title="Summary">
        <span className="text-muted-foreground">{handoff.summary ?? "No handoff yet"}</span>
      </Section>
      <Section title="Changed files">
        {handoff.files.length > 0 ? (
          <ul className="space-y-1 font-mono text-[11px] text-muted-foreground">
            {handoff.files.map((file) => (
              <li key={file}>{file}</li>
            ))}
          </ul>
        ) : (
          <span className="text-muted-foreground">No files recorded</span>
        )}
      </Section>
      <Section title="Validation evidence">
        {handoff.validationEvidence.length > 0 ? (
          <ul className="space-y-2 text-muted-foreground">
            {handoff.validationEvidence.map((item) => (
              <li key={item.label} className="space-y-0.5">
                <div className="flex items-center justify-between gap-2">
                  <span>{item.label}</span>
                  <span
                    className={cn(
                      "rounded border px-1.5 py-0.5 text-[10px]",
                      evidenceTone(item.status),
                    )}
                  >
                    {validationStatusLabel(item.status)}
                  </span>
                </div>
                <p className="text-[11px]">{item.detail}</p>
              </li>
            ))}
          </ul>
        ) : (
          <span className="text-muted-foreground">No validation evidence recorded</span>
        )}
      </Section>
      <Section title="Proof needed">
        {handoff.proofNeeded.length > 0 ? (
          <ul className="space-y-1 text-muted-foreground">
            {handoff.proofNeeded.map((item) => (
              <li key={item}>{item}</li>
            ))}
          </ul>
        ) : (
          <span className="text-muted-foreground">No proof checklist recorded</span>
        )}
      </Section>
      <Section title="Next action">
        <span className="text-muted-foreground">
          {handoff.nextReviewAction ?? "No review action recorded"}
        </span>
      </Section>
      {handoff.branch && (
        <Section title="Review branch">
          <p className="font-mono text-[11px] text-muted-foreground">{handoff.branch}</p>
        </Section>
      )}
      {handoff.curatedSummaryPath && (
        <Section title="Curated summary">
          <p className="font-mono text-[11px] text-muted-foreground">
            {handoff.curatedSummaryPath}
          </p>
        </Section>
      )}
    </Panel>
  );

  const decisionPanel = (
    <ReviewDecisionPanel
      task={task}
      actions={actions}
      pending={pending}
      onAction={onAction}
    />
  );

  const pullRequestPanel = (
    <PullRequestPanel task={task} actions={actions} pending={pending} onAction={onAction} />
  );

  return (
    <div className="space-y-5">
      {reviewFocused ? (
        <>
          {handoffPanel}
          {decisionPanel}
          {pullRequestPanel}
          {runPanel}
        </>
      ) : (
        <>
          {runPanel}
          {handoffPanel}
          {decisionPanel}
          {pullRequestPanel}
        </>
      )}
    </div>
  );
}

function ReviewDecisionPanel({
  task,
  actions,
  pending,
  onAction,
}: {
  task: ServiceTask;
  actions: TaskAction[];
  pending: string | null;
  onAction: (action: TaskAction) => void;
}) {
  const state = reviewGateState(task);
  const decisionActions = actions.filter((action) =>
    action.kind === "event" && action.event === "approve"
      ? true
      : action.kind === "request_changes" || action.kind === "open_pull_request",
  );
  const requestChangesBlocked = task.githubPrState === "open";
  const failedValidation = hasFailedRequiredValidation(task);

  return (
    <Panel title="Review Decision">
      <Section title="State">
        <span
          className={cn(
            "inline-flex rounded-md border px-2 py-0.5",
            reviewGateTone(state) === "ready"
              ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
              : reviewGateTone(state) === "warning"
                ? "border-amber-500/30 bg-amber-500/10 text-amber-700 dark:text-amber-300"
                : "text-muted-foreground",
          )}
        >
          {reviewGateLabel(task)}
        </span>
      </Section>
      {failedValidation && (
        <div className="rounded-md border border-amber-500/30 bg-amber-500/10 p-2 text-amber-800 dark:text-amber-200">
          <p className="text-xs font-medium">{validationSummaryLabel(task)}</p>
          <p className="mt-0.5 text-xs">
            Required validation failed. You can still approve, but requesting changes is
            recommended.
          </p>
        </div>
      )}
      {decisionActions.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {decisionActions.map((action) => (
            <TaskActionControl
              key={action.kind === "event" ? action.event : action.kind}
              action={action}
              pending={pending}
              onAction={onAction}
            />
          ))}
        </div>
      )}
      {requestChangesBlocked && (
        <p className="text-muted-foreground">
          This task already has an open pull request. Request changes on the PR, or close the PR
          before continuing in Symphonia.
        </p>
      )}
    </Panel>
  );
}

function PullRequestPanel({
  task,
  actions,
  pending,
  onAction,
}: {
  task: ServiceTask;
  actions: TaskAction[];
  pending: string | null;
  onAction: (action: TaskAction) => void;
}) {
  const prActions = actions.filter((action) =>
    action.kind === "view_pr" || action.kind === "refresh_pr" || action.kind === "open_pull_request",
  );

  return (
    <Panel title="Pull Request">
      <Section title="State">
        <span className="text-muted-foreground">{prStateLabel(task) ?? "No PR"}</span>
      </Section>
      {task.githubPr && (
        <Section title="Link">
          <a
            href={task.githubPr}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1.5 rounded-md border bg-background px-2 py-1 hover:bg-muted"
          >
            <GitPullRequest className="h-3 w-3" />
            <span>{prStateLabel(task) ?? "linked"}</span>
            <ExternalLink className="h-3 w-3 text-muted-foreground" />
          </a>
        </Section>
      )}
      {task.githubIssue && (
        <Section title="GitHub issue">
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
        </Section>
      )}
      {task.githubPrState === "merged" && (
        <Section title="Merge status">
          <span className="text-muted-foreground">Pull request was merged. Task completed.</span>
        </Section>
      )}
      {task.githubPrState === "closed" && (
        <Section title="Merge status">
          <span className="text-muted-foreground">
            Pull request was closed without merge. Task remains in review.
          </span>
        </Section>
      )}
      {prActions.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {prActions.map((action) => (
            <TaskActionControl
              key={action.kind === "view_pr" ? action.href : action.kind}
              action={action}
              pending={pending}
              onAction={onAction}
            />
          ))}
        </div>
      )}
    </Panel>
  );
}

function TaskActionControl({
  action,
  pending,
  onAction,
}: {
  action: TaskAction;
  pending: string | null;
  onAction: (action: TaskAction) => void;
}) {
  if (action.kind === "view_pr") {
    return (
      <a
        href={action.href}
        target="_blank"
        rel="noreferrer"
        className="inline-flex items-center gap-1.5 rounded-md border bg-background px-2 py-1 hover:bg-muted"
      >
        {action.icon}
        {action.label}
      </a>
    );
  }

  const pendingKey = action.kind === "event" ? action.event : action.kind;

  return (
    <button
      type="button"
      onClick={() => onAction(action)}
      disabled={pending != null}
      className={cn(
        "inline-flex items-center gap-1.5 rounded-md border bg-background px-2 py-1 hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50",
        action.primary && "bg-primary text-primary-foreground hover:opacity-90",
      )}
    >
      {action.icon}
      {pending === pendingKey ? "Working..." : action.label}
    </button>
  );
}

function OpenPullRequestConfirmation({
  task,
  pending,
  onCancel,
  onConfirm,
}: {
  task: ServiceTask;
  pending: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  const handoff = reviewHandoffForTask(task);
  const details = openPullRequestDetails(task, handoff);

  return (
    <div className="mt-4 rounded-md border border-sky-500/30 bg-sky-500/10 p-3">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h2 className="text-sm font-medium">Open Pull Request</h2>
          <p className="mt-1 text-xs text-muted-foreground">
            This will publish the review branch to GitHub and create a pull request.
            No automatic merge will happen. Symphonia will not merge it automatically.
          </p>
        </div>
        <GitPullRequest className="h-4 w-4 text-sky-600 dark:text-sky-400" />
      </div>
      <dl className="mt-3 grid gap-2 text-xs sm:grid-cols-2">
        <ReviewDetail label="Base branch" value={details.baseBranch} />
        <ReviewDetail label="Head branch" value={details.headBranch} />
        <ReviewDetail label="Changed files" value={String(details.changedFilesCount)} />
        <ReviewDetail label="Curated summary" value={details.curatedSummaryPath} />
        <ReviewDetail label="Linked issue" value={details.linkedIssue} />
      </dl>
      <div className="mt-3 flex justify-end gap-2">
        <button
          type="button"
          onClick={onCancel}
          disabled={pending}
          className="rounded-md border bg-background px-2.5 py-1 text-xs hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
        >
          Cancel
        </button>
        <button
          type="button"
          onClick={onConfirm}
          disabled={pending}
          className="inline-flex items-center gap-1.5 rounded-md bg-primary px-2.5 py-1 text-xs text-primary-foreground hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
        >
          <GitPullRequest className="h-3.5 w-3.5" />
          {pending ? "Opening..." : "Open Pull Request"}
        </button>
      </div>
    </div>
  );
}

function ReviewDetail({ label, value }: { label: string; value?: string }) {
  return (
    <div>
      <dt className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
        {label}
      </dt>
      <dd className="mt-0.5 break-words font-mono text-[11px] text-foreground">
        {value ?? "Not recorded"}
      </dd>
    </div>
  );
}

function openPullRequestDetails(task: ServiceTask, handoff: ReturnType<typeof reviewHandoffForTask>) {
  const baseBranch =
    safeReviewBranch(task.handoff?.baseBranch) ??
    safeReviewBranch(task.github?.pull_request?.base_branch) ??
    safeReviewBranch(task.github?.repo?.default_branch) ??
    "main";
  const headBranch =
    safeReviewBranch(task.handoff?.headBranch ?? task.run?.reviewBranch) ?? "Not recorded";
  const linkedIssue = task.github?.issue?.number
    ? `#${task.github.issue.number}`
    : task.githubIssue ?? "Not linked";

  return {
    baseBranch,
    headBranch,
    changedFilesCount: handoff.files.length,
    curatedSummaryPath: handoff.curatedSummaryPath ?? "Not recorded",
    linkedIssue,
  };
}

function validationStatusLabel(status: string): string {
  if (status === "passed") return "Passed";
  if (status === "failed") return "Failed";
  return "Not run";
}

function evidenceTone(status: string): string {
  if (status === "passed") {
    return "border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300";
  }

  if (status === "failed") {
    return "border-red-500/30 bg-red-500/10 text-red-700 dark:text-red-300";
  }

  return "border-muted-foreground/20 bg-background text-muted-foreground";
}

function recoveryMessageForTask(task: ServiceTask): string | undefined {
  if (task.run?.state === "canceled" || task.status === "canceled") {
    return "Run canceled. The task is paused and can be retried.";
  }

  if (task.pausedReason === "blocked_by_setup") {
    return "Codex setup is blocked. Fix setup, then retry.";
  }

  if (task.pausedReason === "waiting_for_user") {
    return "Codex needs input before continuing.";
  }

  if (task.pausedReason === "waiting_for_sync") {
    return "Retry scheduled. Harness will retry this task when the backoff expires.";
  }

  if (task.pausedReason === "run_failed") {
    const explanation = task.pausedExplanation ?? "";

    if (
      /no reviewable files/i.test(explanation) ||
      /did not produce any files/i.test(explanation)
    ) {
      return "Codex ran, but no reviewable files were produced. Clarify the task and retry.";
    }

    return "Codex could not produce a reviewable handoff. Edit the task brief or retry.";
  }

  return undefined;
}

function safeMessage(error: unknown, fallback: string): string {
  const message = error instanceof Error ? error.message : fallback;

  return message
    .replace(/(^|[\s(])\/(?:Users|private|tmp|var|Volumes|home|opt|usr)\/[^\s)]+/g, "$1[local path hidden]")
    .replace(/\b[A-Z][A-Z0-9_]*(TOKEN|SECRET|KEY|PASSWORD)=\S+/g, "[environment value hidden]");
}

function Section({
  id,
  title,
  children,
}: {
  id?: string;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <div id={id}>
      <h3 className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
        {title}
      </h3>
      <div className="mt-1">{children}</div>
    </div>
  );
}

function Panel({
  id,
  title,
  children,
}: {
  id?: string;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section id={id} className="border-b pb-4 last:border-b-0">
      <h2 className="text-sm font-semibold tracking-tight">{title}</h2>
      <div className="mt-3 space-y-3">{children}</div>
    </section>
  );
}

function actionsForTask(task: ServiceTask): TaskAction[] {
  switch (task.status) {
    case "todo":
      return [
        {
          label: "Ask Codex to work on this task",
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
      if (task.pausedReason !== "run_failed" && task.pausedReason !== "blocked_by_setup") {
        return [];
      }

      return [
        {
          label: "Retry with Codex",
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

      if (task.githubPrState === "closed") {
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
          },
          ...(canRequestChanges(task)
            ? [
                {
                  label: "Request changes",
                  kind: "request_changes" as const,
                  icon: <RotateCcw className="h-3.5 w-3.5" />,
                  primary: true,
                },
              ]
            : []),
        ];
      }

      if (canOpenPullRequest(task)) {
        return [
          {
            label: "Open Pull Request",
            kind: "open_pull_request",
            icon: <GitPullRequest className="h-3.5 w-3.5" />,
            primary: true,
          },
          ...(canRequestChanges(task)
            ? [
                {
                  label: "Request changes",
                  kind: "request_changes" as const,
                  icon: <RotateCcw className="h-3.5 w-3.5" />,
                },
              ]
            : []),
        ];
      }

      if (!canRequestChanges(task)) return [];

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
