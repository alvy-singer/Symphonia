"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  PRIORITY_LABELS,
  type Priority,
} from "@/data/mock";
import {
  TASK_STATUS_LABELS,
  TASK_STATUS_ORDER,
  pausedReasonLabel,
  type ServiceTask,
  type TaskEligibilityExplanation,
  type TaskLifecycleEvent,
  type TaskStatus,
} from "@/lib/task-model";
import { TaskStatusIcon } from "@/components/icons/task-status-icons";
import { PriorityIcon } from "@/components/icons/status-icons";
import { UserAvatar } from "@/components/avatar-stack";
import { useNewTask } from "@/components/new-task-dialog";
import { cn } from "@/lib/utils";
import { harnessLabel, harnessStatusForTask, isActiveRun } from "@/lib/harness-ui-model";
import type { RepositoryAutomationState, WorkspaceState } from "@/lib/repository-model";
import {
  Bot,
  Filter,
  Plus,
  SlidersHorizontal,
  LayoutGrid,
  List,
} from "lucide-react";

async function fetchTasks(repoKey: string): Promise<ServiceTask[]> {
  const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/tasks`, {
    cache: "no-store",
  });
  if (!res.ok) throw new Error("Could not load tasks");
  const payload = (await res.json()) as { tasks: ServiceTask[] };
  return payload.tasks;
}

async function fetchAutomation(repoKey: string): Promise<RepositoryAutomationState> {
  const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/automation`, {
    cache: "no-store",
  });
  const payload = (await res.json()) as {
    automation?: RepositoryAutomationState;
    error?: string;
  };
  if (!res.ok || !payload.automation) {
    throw new Error(payload.error ?? "Could not load automation");
  }
  return payload.automation;
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
  const payload = (await res.json()) as { task: ServiceTask };
  return payload.task;
}

async function openPullRequest(repoKey: string, taskKey: string): Promise<ServiceTask> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(taskKey)}/open-pull-request`,
    { method: "POST" },
  );
  const payload = (await res.json()) as { task?: ServiceTask; error?: string };
  if (!res.ok || !payload.task) throw new Error(payload.error ?? "Could not open pull request");
  return payload.task;
}

async function refreshPullRequest(repoKey: string, taskKey: string): Promise<ServiceTask> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(taskKey)}/refresh-pr`,
    { method: "POST" },
  );
  const payload = (await res.json()) as { task?: ServiceTask; error?: string };
  if (!res.ok || !payload.task) throw new Error(payload.error ?? "Could not refresh pull request");
  return payload.task;
}

async function startCodingAssistantRun(repoKey: string, taskKey: string): Promise<ServiceTask> {
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
  const payload = (await res.json()) as { task?: ServiceTask; error?: string };
  if (!res.ok || !payload.task) {
    throw new Error(payload.error ?? "Could not start Clarise");
  }
  return payload.task;
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
  const payload = (await res.json()) as { task?: ServiceTask; error?: string };
  if (!res.ok || !payload.task) {
    throw new Error(payload.error ?? "Could not cancel Clarise run");
  }
  return payload.task;
}

type TaskAction =
  | {
      label: string;
      kind: "event";
      event: TaskLifecycleEvent;
      primary?: boolean;
      params?: Record<string, unknown>;
    }
  | {
      label: string;
      kind: "coding_assistant_run" | "cancel_run" | "open_pull_request" | "refresh_pr";
      primary?: boolean;
    }
  | {
      label: string;
      kind: "view_pr";
      href: string;
    }
  | {
      label: string;
      kind: "open_task";
      primary?: boolean;
    };

function TaskCard({
  task,
  repoSlug,
  onEvent,
  pending,
  eligibility,
}: {
  task: ServiceTask;
  repoSlug: string;
  onEvent: (
    task: ServiceTask,
    action: TaskAction,
  ) => void;
  pending: boolean;
  eligibility?: TaskEligibilityExplanation;
}) {
  const pausedReason = pausedReasonLabel(task.pausedReason);
  const activeRun = task.run && isActiveRun(task.run) ? task.run : null;
  const harnessStatus = harnessStatusForTask(task, eligibility);
  return (
    <article className="rounded-md border bg-card p-2.5 text-card-foreground shadow-sm transition-colors hover:border-foreground/20">
      <Link href={`/r/${repoSlug}/tasks/${encodeURIComponent(task.key)}`} className="block">
        <div className="flex items-center gap-2 text-[11px] text-muted-foreground tabular-nums">
          <PriorityIcon priority={task.priority} />
          <span>{task.key}</span>
        </div>
        <p className="mt-1.5 text-sm leading-snug line-clamp-2">{task.title}</p>
        <div className="mt-2 flex flex-wrap gap-1">
          {pausedReason && (
            <span className="inline-flex items-center rounded-full border border-orange-500/30 bg-orange-500/10 px-1.5 py-0.5 text-[10px] text-orange-600 dark:text-orange-400">
              {pausedReason}
            </span>
          )}
          {task.githubPrState === "open" && (
            <span className="inline-flex items-center rounded-full border border-violet-500/30 bg-violet-500/10 px-1.5 py-0.5 text-[10px] text-violet-600 dark:text-violet-400">
              PR Open
            </span>
          )}
          {activeRun && (
            <span className="inline-flex items-center rounded-full border border-sky-500/30 bg-sky-500/10 px-1.5 py-0.5 text-[10px] text-sky-600 dark:text-sky-400">
              {activeRun.currentStep ?? activeRun.label ?? "Working"}
            </span>
          )}
          {harnessStatus && (
            <span
              className={cn(
                "inline-flex items-center rounded-full border px-1.5 py-0.5 text-[10px]",
                harnessStatus.tone === "ready"
                  ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
                  : harnessStatus.tone === "warning"
                    ? "border-amber-500/30 bg-amber-500/10 text-amber-700 dark:text-amber-300"
                    : "text-muted-foreground",
              )}
              title={harnessStatus.reason}
            >
              {harnessStatus.label}
            </span>
          )}
          {task.project && (
            <span className="inline-flex items-center rounded-full border px-1.5 py-0.5 text-[10px] text-muted-foreground">
              {task.project}
            </span>
          )}
        </div>
      </Link>
      <div className="mt-2 flex items-center justify-between">
        <span className="text-[10px] text-muted-foreground">{task.assistant ?? "Unassigned"}</span>
        {task.assignee && <UserAvatar user={task.assignee} size={18} />}
      </div>
      <TaskActionBar task={task} repoSlug={repoSlug} onEvent={onEvent} pending={pending} compact />
    </article>
  );
}

function TaskRow({
  task,
  repoSlug,
  onEvent,
  pending,
  eligibility,
}: {
  task: ServiceTask;
  repoSlug: string;
  onEvent: (
    task: ServiceTask,
    action: TaskAction,
  ) => void;
  pending: boolean;
  eligibility?: TaskEligibilityExplanation;
}) {
  const pausedReason = pausedReasonLabel(task.pausedReason);
  const activeRun = task.run && isActiveRun(task.run) ? task.run : null;
  const harnessStatus = harnessStatusForTask(task, eligibility);
  return (
    <div className="grid grid-cols-[1.5rem_4.5rem_1fr_auto] items-center gap-3 border-b px-4 py-2 last:border-b-0 hover:bg-muted/40">
      <Link
        href={`/r/${repoSlug}/tasks/${encodeURIComponent(task.key)}`}
        className="contents"
      >
        <TaskStatusIcon status={task.status} />
        <span className="text-[11px] tabular-nums text-muted-foreground">{task.key}</span>
        <div className="min-w-0 flex items-center gap-2">
          <PriorityIcon priority={task.priority} />
          <span className="text-sm truncate">{task.title}</span>
        </div>
      </Link>
      <div className="flex items-center gap-2">
        {pausedReason && (
          <span className="hidden md:inline-flex rounded-full border border-orange-500/30 bg-orange-500/10 px-1.5 py-0.5 text-[10px] text-orange-600 dark:text-orange-400">
            {pausedReason}
          </span>
        )}
        {task.githubPrState === "open" && (
          <span className="hidden md:inline-flex rounded-full border border-violet-500/30 bg-violet-500/10 px-1.5 py-0.5 text-[10px] text-violet-600 dark:text-violet-400">
            PR Open
          </span>
        )}
        {activeRun && (
          <span className="hidden md:inline-flex rounded-full border border-sky-500/30 bg-sky-500/10 px-1.5 py-0.5 text-[10px] text-sky-600 dark:text-sky-400">
            {activeRun.currentStep ?? activeRun.label ?? "Working"}
          </span>
        )}
        {harnessStatus && (
          <span
            className={cn(
              "hidden md:inline-flex rounded-full border px-1.5 py-0.5 text-[10px]",
              harnessStatus.tone === "ready"
                ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
                : harnessStatus.tone === "warning"
                  ? "border-amber-500/30 bg-amber-500/10 text-amber-700 dark:text-amber-300"
                  : "text-muted-foreground",
            )}
            title={harnessStatus.reason}
          >
            {harnessStatus.label}
          </span>
        )}
        {task.assignee && <UserAvatar user={task.assignee} size={20} />}
        <TaskActionBar task={task} repoSlug={repoSlug} onEvent={onEvent} pending={pending} />
      </div>
    </div>
  );
}

const PRIORITIES: Priority[] = ["urgent", "high", "medium", "low", "no-priority"];

async function fetchWorkspace(repoKey: string): Promise<WorkspaceState> {
  const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/workspace`, {
    cache: "no-store",
  });
  const payload = (await res.json()) as { workspace?: WorkspaceState; error?: string };
  if (!res.ok || !payload.workspace) throw new Error(payload.error ?? "Could not load workspace");
  return payload.workspace;
}

async function initializeWorkspace(repoKey: string): Promise<WorkspaceState> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/workspace/initialize`,
    { method: "POST" },
  );
  const payload = (await res.json()) as { workspace?: WorkspaceState; error?: string };
  if (!res.ok || !payload.workspace) {
    throw new Error(payload.error ?? "Could not create workspace folders");
  }
  return payload.workspace;
}

/**
 * Repository Tasks board/list, the locked default landing view.
 *
 * - Board is the default mode and the chosen mode is remembered per repo
 *   in localStorage (and is also driven by the command palette).
 * - Cards link to the brief-first Task page powered by the Markdown editor.
 */
export function TasksView({ repoKey }: { repoKey: string }) {
  const [view, setView] = useState<"board" | "list">("board");
  const [priority, setPriority] = useState<Priority | "all">("all");
  const [tasks, setTasks] = useState<ServiceTask[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [workspace, setWorkspace] = useState<WorkspaceState | null>(null);
  const [automation, setAutomation] = useState<RepositoryAutomationState | null>(null);
  const [eligibilityByTask, setEligibilityByTask] = useState<
    Record<string, TaskEligibilityExplanation>
  >({});
  const [workspacePending, setWorkspacePending] = useState(false);
  const [pendingKey, setPendingKey] = useState<string | null>(null);
  const [sourceMilestone, setSourceMilestone] = useState<string | null>(null);
  const [createdTaskKeys, setCreatedTaskKeys] = useState<string[]>([]);
  const newTask = useNewTask();
  const repoSlug = repoKey.toLowerCase();

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const milestone = params.get("sourceMilestone");
    const created = params
      .get("created")
      ?.split(",")
      .map((key) => key.trim())
      .filter(Boolean);

    if (milestone) setSourceMilestone(milestone);
    if (created?.length) setCreatedTaskKeys(created);
  }, []);

  // Hydrate the per-repo view mode from localStorage and listen for command
  // palette toggles ("Switch to Board / List" actions).
  useEffect(() => {
    try {
      const stored = window.localStorage.getItem(`symphonia.viewMode.${repoKey}`);
      if (stored === "board" || stored === "list") setView(stored);
    } catch {
      /* ignore */
    }
    const handler = (e: Event) => {
      const ce = e as CustomEvent<{ repoKey: string; mode: "board" | "list" }>;
      if (ce.detail?.repoKey === repoKey) setView(ce.detail.mode);
    };
    window.addEventListener("symphonia:viewMode", handler as EventListener);
    return () =>
      window.removeEventListener("symphonia:viewMode", handler as EventListener);
  }, [repoKey]);

  useEffect(() => {
    if (!tasks.some((task) => task.run && isActiveRun(task.run))) return;

    let cancelled = false;
    const interval = window.setInterval(() => {
      fetchTasks(repoKey)
        .then((nextTasks) => {
          if (!cancelled) setTasks(nextTasks);
        })
        .catch((err: unknown) => {
          if (!cancelled) setError(err instanceof Error ? err.message : "Could not load tasks");
        });
    }, 2500);

    return () => {
      cancelled = true;
      window.clearInterval(interval);
    };
  }, [repoKey, tasks]);

  const setMode = (mode: "board" | "list") => {
    setView(mode);
    try {
      window.localStorage.setItem(`symphonia.viewMode.${repoKey}`, mode);
    } catch {
      /* ignore */
    }
  };

  const filtered = useMemo(
    () =>
      tasks.filter(
        (i) =>
          (priority === "all" || i.priority === priority) &&
          (!sourceMilestone || i.sourceMilestone === sourceMilestone),
      ),
    [tasks, priority, sourceMilestone],
  );

  const sourceMilestoneTaskCount = useMemo(
    () =>
      sourceMilestone
        ? tasks.filter((task) => task.sourceMilestone === sourceMilestone).length
        : 0,
    [sourceMilestone, tasks],
  );

  const grouped = useMemo(() => {
    const m = {} as Record<TaskStatus, ServiceTask[]>;
    for (const s of TASK_STATUS_ORDER) m[s] = [];
    for (const i of filtered) m[i.status].push(i);
    return m;
  }, [filtered]);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    Promise.all([fetchWorkspace(repoKey), fetchTasks(repoKey), fetchAutomation(repoKey)])
      .then(([nextWorkspace, nextTasks, nextAutomation]) => {
        if (!cancelled) {
          setWorkspace(nextWorkspace);
          setTasks(nextTasks);
          setAutomation(nextAutomation);
        }
      })
      .catch((err: unknown) => {
        if (!cancelled) setError(err instanceof Error ? err.message : "Could not load tasks");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [repoKey]);

  const todoTaskKeys = useMemo(
    () => tasks.filter((task) => task.status === "todo").map((task) => task.key).join(","),
    [tasks],
  );

  useEffect(() => {
    const keys = todoTaskKeys.split(",").filter(Boolean);
    if (keys.length === 0) {
      setEligibilityByTask({});
      return;
    }

    let cancelled = false;
    Promise.all(
      keys.map(async (key) => [key, await fetchEligibility(repoKey, key)] as const),
    )
      .then((entries) => {
        if (!cancelled) setEligibilityByTask(Object.fromEntries(entries));
      })
      .catch(() => {
        if (!cancelled) setEligibilityByTask({});
      });
    return () => {
      cancelled = true;
    };
  }, [repoKey, todoTaskKeys]);

  useEffect(() => {
    const handler = (event: Event) => {
      const detail = (event as CustomEvent<{ repoKey: string; task: ServiceTask }>).detail;
      if (detail?.repoKey !== repoKey) return;
      setTasks((current) => [
        detail.task,
        ...current.filter((task) => task.key !== detail.task.key),
      ]);
    };
    window.addEventListener("symphonia:taskCreated", handler as EventListener);
    return () => window.removeEventListener("symphonia:taskCreated", handler as EventListener);
  }, [repoKey]);

  const onEvent = async (
    task: ServiceTask,
    action: TaskAction,
  ) => {
    if (action.kind === "view_pr" || action.kind === "open_task") return;

    const eventParams = action.kind === "event" ? action.params : undefined;
    setPendingKey(task.key);
    try {
      const updated =
        action.kind === "event"
          ? await postTaskEvent(repoKey, task.key, action.event, eventParams)
          : action.kind === "coding_assistant_run"
            ? await startCodingAssistantRun(repoKey, task.key)
            : action.kind === "cancel_run" && task.run
            ? await cancelCodingAssistantRun(repoKey, task.key, task.run.id)
            : action.kind === "open_pull_request"
            ? await openPullRequest(repoKey, task.key)
            : await refreshPullRequest(repoKey, task.key);
      setTasks((current) => current.map((item) => (item.key === updated.key ? updated : item)));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not update task");
    } finally {
      setPendingKey(null);
    }
  };

  const createWorkspaceFolders = async () => {
    setWorkspacePending(true);
    setError(null);
    try {
      setWorkspace(await initializeWorkspace(repoKey));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not create workspace folders");
    } finally {
      setWorkspacePending(false);
    }
  };

  const clearSourceMilestone = () => {
    setSourceMilestone(null);
    setCreatedTaskKeys([]);
    window.history.replaceState({}, "", window.location.pathname);
  };

  return (
    <div className="flex h-full flex-col">
      <header className="flex flex-wrap items-center justify-between gap-3 border-b px-4 py-2.5">
        <div className="flex items-center gap-2 text-sm">
          <span className="font-semibold">Tasks</span>
          <span className="text-muted-foreground tabular-nums">{filtered.length}</span>
          <span
            className={cn(
              "inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px]",
              automation?.enabled
                ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
                : "text-muted-foreground",
            )}
          >
            <Bot className="h-3 w-3" />
            {harnessLabel(automation)}
          </span>
          {sourceMilestone && (
            <span className="rounded-full border px-2 py-0.5 text-[11px] text-muted-foreground">
              {sourceMilestone}
            </span>
          )}
        </div>
        <div className="flex items-center gap-1">
          <div className="flex items-center rounded-md border p-0.5" role="group" aria-label="View mode">
            <button
              onClick={() => setMode("board")}
              aria-pressed={view === "board"}
              className={cn(
                "inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[12px]",
                view === "board" ? "bg-muted text-foreground" : "text-muted-foreground",
              )}
            >
              <LayoutGrid className="h-3.5 w-3.5" /> Board
            </button>
            <button
              onClick={() => setMode("list")}
              aria-pressed={view === "list"}
              className={cn(
                "inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[12px]",
                view === "list" ? "bg-muted text-foreground" : "text-muted-foreground",
              )}
            >
              <List className="h-3.5 w-3.5" /> List
            </button>
          </div>
          <select
            value={priority}
            onChange={(e) => setPriority(e.target.value as Priority | "all")}
            aria-label="Filter by priority"
            className="rounded-md border bg-background px-2 py-1 text-[12px]"
          >
            <option value="all">All priorities</option>
            {PRIORITIES.map((p) => (
              <option key={p} value={p}>
                {PRIORITY_LABELS[p]}
              </option>
            ))}
          </select>
          <button
            disabled
            title="Coming soon"
            className="inline-flex cursor-not-allowed items-center gap-1.5 rounded-md border px-2 py-1 text-[12px] text-muted-foreground opacity-60"
          >
            <Filter className="h-3.5 w-3.5" /> Filter
          </button>
          <button
            disabled
            title="Coming soon"
            className="inline-flex cursor-not-allowed items-center gap-1.5 rounded-md border px-2 py-1 text-[12px] text-muted-foreground opacity-60"
          >
            <SlidersHorizontal className="h-3.5 w-3.5" /> Display
          </button>
          <button
            onClick={() => newTask.open()}
            className="inline-flex items-center gap-1.5 rounded-md bg-primary text-primary-foreground px-2 py-1 text-[12px] hover:opacity-90"
          >
            <Plus className="h-3.5 w-3.5" /> New task
          </button>
        </div>
      </header>

      {error && (
        <div className="border-b border-amber-500/30 bg-amber-500/10 px-4 py-2 text-xs text-amber-700 dark:text-amber-300">
          {error}
        </div>
      )}

      {automation && !automation.enabled && !loading && (
        <div className="border-b bg-muted/30 px-4 py-2 text-xs text-muted-foreground">
          Clarise automation is turned off. You can still assign and manage tasks manually.
        </div>
      )}

      {sourceMilestone && !loading && (
        <div className="border-b bg-emerald-500/10 px-4 py-3 text-sm">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="font-medium text-emerald-800 dark:text-emerald-200">
                Task handoff ready
              </p>
              <p className="mt-1 text-muted-foreground">
                Showing {sourceMilestoneTaskCount} To-do tasks from {sourceMilestone}
                {createdTaskKeys.length > 0 ? ` (${createdTaskKeys.join(", ")})` : ""}. Review the
                breakdown here, then assign one when the team is ready to start work.
              </p>
            </div>
            <div className="flex shrink-0 flex-wrap gap-2">
              <Link
                href={`/r/${repoSlug}/workspace`}
                className="rounded-md border bg-background px-2 py-1 text-xs hover:bg-muted"
              >
                Back to planning
              </Link>
              <button
                onClick={clearSourceMilestone}
                className="rounded-md border bg-background px-2 py-1 text-xs hover:bg-muted"
              >
                Show all tasks
              </button>
            </div>
          </div>
        </div>
      )}

      {workspace && (!workspace.initialized || !workspace.workflow.exists) && (
        <div className="border-b bg-muted/30 px-4 py-2 text-xs">
          <div className="flex flex-wrap items-center gap-2">
            {!workspace.initialized && (
              <>
                <span className="text-muted-foreground">This repository needs to be set up.</span>
                <button
                  onClick={createWorkspaceFolders}
                  disabled={workspacePending}
                  className="rounded-md border bg-background px-2 py-1 hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
                >
                  {workspacePending ? "Setting up…" : "Set up repository"}
                </button>
              </>
            )}
            {!workspace.workflow.exists && (
              <>
                <span className="text-muted-foreground">Automation rules haven&apos;t been set up yet.</span>
                <Link
                  href={`/r/${repoSlug}/workflow`}
                  className="rounded-md border bg-background px-2 py-1 hover:bg-muted"
                >
                  Set up automation
                </Link>
              </>
            )}
          </div>
        </div>
      )}

      {loading ? (
        <div className="grid flex-1 place-items-center text-sm text-muted-foreground">
          Loading tasks…
        </div>
      ) : view === "board" ? (
        <div className="relative flex-1 overflow-hidden">
          <div className="h-full overflow-auto">
            <div className="flex min-w-max gap-3 p-3">
            {TASK_STATUS_ORDER.map((s) => (
              <div
                key={s}
                className="flex w-72 shrink-0 flex-col rounded-lg border bg-muted/30"
                role="list"
                aria-label={`${TASK_STATUS_LABELS[s]} (${grouped[s].length})`}
              >
                <div className="flex items-center gap-2 px-3 py-2 border-b">
                  <TaskStatusIcon status={s} />
                  <span className="text-sm font-medium">{TASK_STATUS_LABELS[s]}</span>
                  <span className="text-[11px] text-muted-foreground tabular-nums">
                    {grouped[s].length}
                  </span>
                  <button
                    onClick={() => newTask.open()}
                    aria-label={`New task in ${TASK_STATUS_LABELS[s]}`}
                    className="ml-auto grid h-5 w-5 place-items-center rounded hover:bg-background text-muted-foreground"
                  >
                    <Plus className="h-3 w-3" />
                  </button>
                </div>
                <div className="flex flex-col gap-2 p-2">
                  {grouped[s].map((i) => (
                    <TaskCard
                      key={i.key}
                      task={i}
                      repoSlug={repoSlug}
                      onEvent={onEvent}
                      pending={pendingKey === i.key}
                      eligibility={eligibilityByTask[i.key]}
                    />
                  ))}
                  {grouped[s].length === 0 && (
                    <div className="rounded-md border border-dashed p-3 text-center text-[11px] text-muted-foreground">
                      Tasks are units of work. Create one, or connect GitHub to import issues.
                    </div>
                  )}
                </div>
              </div>
            ))}
            </div>
          </div>
          <div
            className="pointer-events-none absolute right-0 top-0 hidden h-full w-8 bg-gradient-to-l from-background to-transparent md:block"
            aria-hidden="true"
          />
        </div>
      ) : (
        <div className="flex-1 overflow-auto">
          {TASK_STATUS_ORDER.map((s) =>
            grouped[s].length === 0 ? null : (
              <section key={s} className="border-b last:border-b-0">
                <div className="flex items-center gap-2 px-4 py-2 bg-muted/30">
                  <TaskStatusIcon status={s} />
                  <span className="text-sm font-medium">{TASK_STATUS_LABELS[s]}</span>
                  <span className="text-[11px] text-muted-foreground tabular-nums">
                    {grouped[s].length}
                  </span>
                </div>
                {grouped[s].map((i) => (
                  <TaskRow
                    key={i.key}
                    task={i}
                    repoSlug={repoSlug}
                    onEvent={onEvent}
                    pending={pendingKey === i.key}
                    eligibility={eligibilityByTask[i.key]}
                  />
                ))}
              </section>
            ),
          )}
        </div>
      )}
    </div>
  );
}

function TaskActionBar({
  task,
  repoSlug,
  onEvent,
  pending,
  compact,
}: {
  task: ServiceTask;
  repoSlug: string;
  onEvent: (
    task: ServiceTask,
    action: TaskAction,
  ) => void;
  pending: boolean;
  compact?: boolean;
}) {
  const actions = actionsForTask(task);
  if (actions.length === 0) return null;

  return (
    <div className={cn("flex flex-wrap gap-1", compact ? "mt-2" : "")}>
      {actions.map((action) => (
        action.kind === "view_pr" ? (
          <a
            key={action.kind}
            href={action.href}
            target="_blank"
            rel="noreferrer"
            className="rounded-md border px-1.5 py-0.5 text-[10px] text-muted-foreground hover:bg-muted hover:text-foreground"
          >
            {action.label}
          </a>
        ) : action.kind === "open_task" ? (
          <Link
            key={action.kind}
            href={`/r/${repoSlug}/tasks/${encodeURIComponent(task.key)}`}
            className={cn(
              "rounded-md border px-1.5 py-0.5 text-[10px] text-muted-foreground hover:bg-muted hover:text-foreground",
              action.primary && "border-primary/30 bg-primary/5 text-foreground",
            )}
          >
            {action.label}
          </Link>
        ) : (
          <button
            key={action.kind === "event" ? action.event : action.kind}
            onClick={() => onEvent(task, action)}
            disabled={pending}
            className={cn(
              "rounded-md border px-1.5 py-0.5 text-[10px] text-muted-foreground hover:bg-muted hover:text-foreground disabled:cursor-not-allowed disabled:opacity-50",
              action.primary && "border-primary/30 bg-primary/5 text-foreground",
            )}
          >
            {pending ? "Working…" : action.label}
          </button>
        )
      ))}
    </div>
  );
}

function actionsForTask(task: ServiceTask): TaskAction[] {
  switch (task.status) {
    case "todo":
      return [{ label: "Assign", kind: "coding_assistant_run", primary: true }];
    case "in_progress":
      return task.run && isActiveRun(task.run)
        ? [{ label: "Cancel run", kind: "cancel_run" }]
        : [];
    case "paused":
      return task.pausedReason === "run_failed"
        ? [{ label: "Retry", kind: "coding_assistant_run", primary: true }]
        : [];
    case "in_review":
      if (task.githubPrState === "open") {
        return [
          ...(task.githubPr ? [{ label: "View PR", kind: "view_pr" as const, href: task.githubPr }] : []),
          { label: "Refresh PR", kind: "refresh_pr", primary: true },
        ];
      }
      if (task.reviewApproved) {
        return [{ label: "Open PR", kind: "open_pull_request", primary: true }];
      }
      return [
        { label: "Approve", kind: "event", event: "approve", primary: true },
        { label: "Request changes", kind: "open_task" },
      ];
    case "completed":
    case "canceled":
      return [];
  }
}
