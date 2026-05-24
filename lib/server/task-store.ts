import { promises as fs } from "node:fs";
import path from "node:path";
import type { ServiceTask, TaskLifecycleEvent } from "@/lib/task-model";
import {
  frontmatterToTask,
  parseTaskMarkdown,
  serializeTaskMarkdown,
} from "@/lib/server/task-markdown";

type Frontmatter = Record<string, string | boolean | string[] | null | undefined>;

const REPOSITORIES_ROOT =
  process.env.SYMPHONIA_REPOSITORIES_ROOT ??
  path.join(process.cwd(), "fixtures", "repositories");

export async function listRepositoryTasks(repoKey: string): Promise<ServiceTask[]> {
  const taskDir = path.join(repositoryRoot(repoKey), "symphonia", "tasks");
  let entries: string[];
  try {
    entries = await fs.readdir(taskDir);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw error;
  }
  const markdownFiles = entries.filter((entry) => entry.endsWith(".md")).sort();
  const tasks = await Promise.all(
    markdownFiles.map((file) => readTaskFile(repoKey, path.join(taskDir, file))),
  );
  return tasks.sort(
    (a, b) => (a.updatedAt ?? "").localeCompare(b.updatedAt ?? "") * -1,
  );
}

export async function getRepositoryTask(
  repoKey: string,
  taskKey: string,
): Promise<ServiceTask | null> {
  const tasks = await listRepositoryTasks(repoKey);
  return tasks.find((task) => task.key === taskKey) ?? null;
}

export async function patchRepositoryTask(
  repoKey: string,
  taskKey: string,
  patch: { title?: string; body?: string; frontmatter?: Frontmatter },
): Promise<ServiceTask> {
  const file = await getTaskFile(repoKey, taskKey);
  const text = await fs.readFile(file, "utf8");
  const parsed = parseTaskMarkdown(text);
  const frontmatter: Frontmatter = {
    ...parsed.frontmatter,
    ...(patch.frontmatter ?? {}),
    updated_at: now(),
  };
  if (patch.title !== undefined) frontmatter.title = patch.title;
  const body = patch.body ?? parsed.body;

  await fs.writeFile(file, serializeTaskMarkdown(frontmatter, body), "utf8");
  return readTaskFile(repoKey, file);
}

export async function applyTaskEvent(
  repoKey: string,
  taskKey: string,
  event: TaskLifecycleEvent,
  params: Record<string, unknown> = {},
): Promise<ServiceTask> {
  const file = await getTaskFile(repoKey, taskKey);
  const text = await fs.readFile(file, "utf8");
  const parsed = parseTaskMarkdown(text);
  const { frontmatter, body } = applyLifecycle(parsed.frontmatter, parsed.body, event, params);

  await fs.writeFile(file, serializeTaskMarkdown(frontmatter, body), "utf8");
  return readTaskFile(repoKey, file);
}

async function readTaskFile(repoKey: string, file: string): Promise<ServiceTask> {
  const text = await fs.readFile(file, "utf8");
  const parsed = parseTaskMarkdown(text);
  const repoRoot = repositoryRoot(repoKey);
  return frontmatterToTask(repoKey, path.relative(repoRoot, file), parsed);
}

async function getTaskFile(repoKey: string, taskKey: string): Promise<string> {
  const task = await getRepositoryTask(repoKey, taskKey);
  if (!task) throw new Error(`Task ${taskKey} not found`);
  return path.join(repositoryRoot(repoKey), task.path);
}

function repositoryRoot(repoKey: string): string {
  return path.join(REPOSITORIES_ROOT, repoKey.toUpperCase());
}

function applyLifecycle(
  frontmatter: Frontmatter,
  body: string,
  event: TaskLifecycleEvent,
  params: Record<string, unknown>,
): { frontmatter: Frontmatter; body: string } {
  const base: Frontmatter = { ...frontmatter, updated_at: now() };
  switch (event) {
    case "start":
      return { frontmatter: { ...base, status: "in_progress" }, body };
    case "submit_review": {
      const key = String(base.key ?? "task");
      return {
        frontmatter: {
          ...base,
          status: "in_review",
          review_approved: false,
          review_summary:
            stringParam(params.summary) ??
            "The Coding Assistant produced a reviewable handoff.",
          files_changed: arrayParam(params.files_changed ?? params.filesChanged) ?? [
            `symphonia/tasks/${key}.md`,
          ],
          next_review_action:
            stringParam(params.next_review_action ?? params.nextReviewAction) ??
            "Review the summary and files changed.",
        },
        body,
      };
    }
    case "fail_run":
      return {
        frontmatter: {
          ...base,
          status: "paused",
          paused_reason: "run_failed",
          paused_explanation:
            stringParam(params.explanation) ??
            "The Coding Assistant could not produce a reviewable handoff.",
        },
        body,
      };
    case "approve": {
      const requiresPr = params.requires_pr !== false && params.requiresPr !== false;
      return {
        frontmatter: {
          ...base,
          status: requiresPr ? "in_review" : "completed",
          review_approved: true,
          next_review_action: requiresPr ? "Open pull request." : null,
        },
        body,
      };
    }
    case "request_changes": {
      const feedback = stringParam(params.feedback) ?? "Please make another pass.";
      const checklist = arrayParam(params.checklist) ?? structureFeedback(feedback);
      return {
        frontmatter: {
          ...base,
          status: "in_progress",
          review_approved: false,
          next_review_action: "Coding Assistant is continuing with requested changes.",
        },
        body: appendReviewNotes(body, feedback, checklist),
      };
    }
    case "open_pr": {
      const pr =
        stringParam(params.github_pr ?? params.githubPr) ??
        "https://github.com/agora-creations/symphonia/pull/1";
      return {
        frontmatter: {
          ...base,
          status: "in_review",
          github_pr: pr,
          github_pr_state: "open",
          next_review_action: "Wait for pull request merge.",
        },
        body,
      };
    }
    case "merge_pr": {
      return {
        frontmatter: {
          ...base,
          status: "completed",
          github_pr_state: "merged",
          github_issue_state:
            base.github_sync_enabled === true || base.github_sync_enabled === "true"
              ? "closed"
              : base.github_issue_state,
          next_review_action: null,
        },
        body: appendTimeline(body, "Pull request merged. Linked GitHub issue updated."),
      };
    }
    case "cancel":
      return { frontmatter: { ...base, status: "canceled" }, body };
  }
}

function structureFeedback(feedback: string): string[] {
  return feedback
    .split(/[\n.;]+/)
    .map((item) => item.trim())
    .filter(Boolean)
    .map((item) => {
      const lower = item.toLowerCase();
      if (
        lower.startsWith("remove ") ||
        lower.startsWith("make ") ||
        lower.startsWith("keep ")
      ) {
        return item.replace(/\.$/, "");
      }
      return `Address: ${item.replace(/\.$/, "")}`;
    });
}

function appendReviewNotes(body: string, feedback: string, checklist: string[]): string {
  return `${body.trimEnd()}

## Review notes

### Changes requested - ${now()}

Original feedback:
${feedback}

Requested changes:
${checklist.map((item) => `- [ ] ${item}`).join("\n")}
`;
}

function appendTimeline(body: string, note: string): string {
  return `${body.trimEnd()}

## Timeline

- ${now()}: ${note}
`;
}

function stringParam(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value : undefined;
}

function arrayParam(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  const items = value.filter((item): item is string => typeof item === "string" && item.length > 0);
  return items.length > 0 ? items : undefined;
}

function now(): string {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}
