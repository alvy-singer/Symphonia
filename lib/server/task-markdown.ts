import type { ServiceTask, TaskStatus, PausedReason } from "@/lib/task-model";

export interface ParsedTaskFile {
  frontmatter: Record<string, string | boolean | string[] | null>;
  body: string;
}

const ORDERED_KEYS = [
  "key",
  "title",
  "status",
  "priority",
  "project",
  "assistant",
  "paused_reason",
  "paused_explanation",
  "github_issue",
  "github_issue_state",
  "github_pr",
  "github_pr_state",
  "github_sync_enabled",
  "review_approved",
  "review_summary",
  "files_changed",
  "next_review_action",
  "updated_at",
];

const VALID_STATUSES = new Set<TaskStatus>([
  "todo",
  "in_progress",
  "in_review",
  "paused",
  "completed",
  "canceled",
]);

const VALID_PAUSED_REASONS = new Set<PausedReason>([
  "run_failed",
  "waiting_for_user",
  "blocked_by_setup",
  "waiting_for_sync",
  "needs_clarification",
]);

export function parseTaskMarkdown(text: string): ParsedTaskFile {
  if (!text.startsWith("---\n")) return { frontmatter: {}, body: text };
  const end = text.indexOf("\n---", 4);
  if (end === -1) return { frontmatter: {}, body: text };

  const raw = text.slice(4, end);
  const body = text.slice(end + "\n---".length).replace(/^\n+/, "");
  const frontmatter = parseFrontmatter(raw);
  return { frontmatter, body };
}

export function serializeTaskMarkdown(
  frontmatter: Record<string, string | boolean | string[] | null | undefined>,
  body: string,
): string {
  const keys = [
    ...ORDERED_KEYS,
    ...Object.keys(frontmatter)
      .filter((key) => !ORDERED_KEYS.includes(key))
      .sort(),
  ];
  const rendered = keys
    .filter((key) => Object.prototype.hasOwnProperty.call(frontmatter, key))
    .map((key) => renderEntry(key, frontmatter[key]))
    .join("\n");

  return `---\n${rendered}\n---\n\n${body.replace(/^\n+/, "")}`;
}

export function frontmatterToTask(
  repo: string,
  repoRelativePath: string,
  parsed: ParsedTaskFile,
): ServiceTask {
  const fm = parsed.frontmatter;
  const status = normalizeStatus(asString(fm.status));
  const pausedReason = normalizePausedReason(asString(fm.paused_reason));
  const key = asString(fm.key) || repoRelativePath.replace(/^.*\/|\.md$/g, "");

  return {
    key,
    title: asString(fm.title) || key,
    status,
    priority: normalizePriority(asString(fm.priority)),
    project: asString(fm.project) || undefined,
    assistant: asString(fm.assistant) || undefined,
    pausedReason,
    pausedExplanation: asString(fm.paused_explanation) || undefined,
    githubIssue: asString(fm.github_issue) || undefined,
    githubIssueState: asString(fm.github_issue_state) || undefined,
    githubPr: asString(fm.github_pr) || undefined,
    githubPrState: asString(fm.github_pr_state) || undefined,
    githubSyncEnabled: asBoolean(fm.github_sync_enabled),
    reviewApproved: asBoolean(fm.review_approved),
    reviewSummary: asString(fm.review_summary) || undefined,
    filesChanged: asStringArray(fm.files_changed),
    nextReviewAction: asString(fm.next_review_action) || undefined,
    updatedAt: asString(fm.updated_at) || undefined,
    repo,
    path: repoRelativePath,
    body: parsed.body,
    labels: labelForStatus(status),
  };
}

function parseFrontmatter(raw: string): ParsedTaskFile["frontmatter"] {
  const lines = raw.split("\n");
  const result: ParsedTaskFile["frontmatter"] = {};
  let currentList: string | null = null;

  for (const line of lines) {
    if (!line.trim()) continue;
    const trimmed = line.trimStart();
    if (trimmed.startsWith("- ") && currentList) {
      const current = result[currentList];
      result[currentList] = [
        ...(Array.isArray(current) ? current : []),
        parseScalar(trimmed.slice(2).trim()) as string,
      ];
      continue;
    }

    const index = line.indexOf(":");
    if (index === -1) {
      currentList = null;
      continue;
    }
    const key = line.slice(0, index).trim();
    const value = line.slice(index + 1).trim();
    if (!value) {
      result[key] = nextLineLooksLikeList(lines, line) ? [] : null;
      currentList = key;
    } else {
      result[key] = parseScalar(value);
      currentList = null;
    }
  }

  return result;
}

function nextLineLooksLikeList(lines: string[], currentLine: string): boolean {
  const currentIndex = lines.indexOf(currentLine);
  const next = lines[currentIndex + 1];
  return !!next && next.trimStart().startsWith("- ");
}

function parseScalar(value: string): string | boolean {
  if (value === "true") return true;
  if (value === "false") return false;
  return value.replace(/^"|"$/g, "");
}

function renderEntry(
  key: string,
  value: string | boolean | string[] | null | undefined,
): string {
  if (Array.isArray(value)) {
    if (value.length === 0) return `${key}:`;
    return [`${key}:`, ...value.map((item) => `  - ${formatScalar(item)}`)].join("\n");
  }
  return `${key}: ${formatScalar(value)}`;
}

function formatScalar(value: string | boolean | null | undefined): string {
  if (value == null) return "";
  if (typeof value === "boolean") return value ? "true" : "false";
  return value;
}

function asString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function asBoolean(value: unknown): boolean {
  return value === true || value === "true";
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string" && item.length > 0);
}

function normalizeStatus(value: string): TaskStatus {
  return VALID_STATUSES.has(value as TaskStatus) ? (value as TaskStatus) : "todo";
}

function normalizePausedReason(value: string): PausedReason | undefined {
  return VALID_PAUSED_REASONS.has(value as PausedReason)
    ? (value as PausedReason)
    : undefined;
}

function normalizePriority(value: string): ServiceTask["priority"] {
  if (value === "urgent" || value === "high" || value === "medium" || value === "low") {
    return value;
  }
  return "no-priority";
}

function labelForStatus(status: TaskStatus): ServiceTask["labels"] {
  const colorByStatus: Record<TaskStatus, string> = {
    todo: "text-zinc-500",
    in_progress: "text-amber-500",
    in_review: "text-violet-500",
    paused: "text-orange-500",
    completed: "text-emerald-500",
    canceled: "text-zinc-500",
  };
  const labelByStatus: Record<TaskStatus, string> = {
    todo: "To-do",
    in_progress: "In Progress",
    in_review: "In Review",
    paused: "Paused",
    completed: "Completed",
    canceled: "Canceled",
  };
  return [{ id: status, name: labelByStatus[status], color: colorByStatus[status] }];
}
