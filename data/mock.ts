// Mock data for the Symphonia preview frontend.
// Vocabulary: Repository (top-level workspace), Project (within a repo), Task
// (work item — what was previously "issue"). Statuses include Symphonia-specific
// states like In Review and Paused that surface around the AI workflow.

export type Priority = "no-priority" | "urgent" | "high" | "medium" | "low";
export type Health = "on-track" | "at-risk" | "off-track" | "no-update";
export type ProjectStatus =
  | "backlog"
  | "planned"
  | "in-progress"
  | "paused"
  | "completed"
  | "cancelled";

export interface User {
  id: string;
  name: string;
  initials: string;
  color: string;
}

export interface Project {
  id: string;
  key: string;
  name: string;
  status: ProjectStatus;
  priority: Priority;
  health: Health;
  progress: number;
  lead: User;
  members: User[];
  startDate?: string;
  targetDate?: string;
  repo: string;
}

export interface Repository {
  id: string;
  key: string; // 3-letter code used in task keys
  name: string; // e.g. "agora-creations/symphonia"
  color: string;
}

export const users: User[] = [
  { id: "u1", name: "Ava Martinez", initials: "AM", color: "bg-rose-500" },
  { id: "u2", name: "Leo Tanaka", initials: "LT", color: "bg-amber-500" },
  { id: "u3", name: "Mira Khan", initials: "MK", color: "bg-emerald-500" },
  { id: "u4", name: "Noah Berg", initials: "NB", color: "bg-sky-500" },
  { id: "u5", name: "Sienna Cole", initials: "SC", color: "bg-violet-500" },
  { id: "u6", name: "Theo Park", initials: "TP", color: "bg-fuchsia-500" },
  { id: "u7", name: "Yuki Ono", initials: "YO", color: "bg-cyan-500" },
  { id: "u8", name: "Eli Romano", initials: "ER", color: "bg-orange-500" },
];

export const repositories: Repository[] = [
  { id: "r1", key: "SYM", name: "agora-creations/symphonia", color: "text-rose-500" },
  { id: "r2", key: "API", name: "agora-creations/api", color: "text-sky-500" },
  { id: "r3", key: "WEB", name: "agora-creations/web", color: "text-violet-500" },
  { id: "r4", key: "OPS", name: "agora-creations/ops", color: "text-emerald-500" },
];

export const projects: Project[] = [
  {
    id: "p1",
    key: "SYM-101",
    name: "Repository overview redesign",
    status: "in-progress",
    priority: "high",
    health: "on-track",
    progress: 64,
    lead: users[0],
    members: [users[0], users[2], users[4]],
    startDate: "2026-04-02",
    targetDate: "2026-06-12",
    repo: "SYM",
  },
  {
    id: "p2",
    key: "API-204",
    name: "Realtime sync engine v2",
    status: "in-progress",
    priority: "urgent",
    health: "at-risk",
    progress: 41,
    lead: users[3],
    members: [users[3], users[1], users[6]],
    startDate: "2026-03-15",
    targetDate: "2026-05-30",
    repo: "API",
  },
  {
    id: "p3",
    key: "WEB-052",
    name: "Marketing site refresh",
    status: "planned",
    priority: "medium",
    health: "no-update",
    progress: 0,
    lead: users[4],
    members: [users[4], users[5]],
    startDate: "2026-05-20",
    targetDate: "2026-07-08",
    repo: "WEB",
  },
  {
    id: "p4",
    key: "OPS-019",
    name: "Billing migration to Stripe",
    status: "in-progress",
    priority: "high",
    health: "on-track",
    progress: 78,
    lead: users[7],
    members: [users[7], users[1]],
    startDate: "2026-02-10",
    targetDate: "2026-05-22",
    repo: "OPS",
  },
  {
    id: "p5",
    key: "API-219",
    name: "Edge cache pipeline",
    status: "backlog",
    priority: "low",
    health: "no-update",
    progress: 0,
    lead: users[6],
    members: [users[6], users[3]],
    targetDate: "2026-08-01",
    repo: "API",
  },
  {
    id: "p6",
    key: "SYM-088",
    name: "Clarise inline drafts",
    status: "paused",
    priority: "medium",
    health: "off-track",
    progress: 22,
    lead: users[2],
    members: [users[2], users[0]],
    startDate: "2026-01-08",
    targetDate: "2026-04-01",
    repo: "SYM",
  },
  {
    id: "p7",
    key: "WEB-061",
    name: "Iconography system",
    status: "completed",
    priority: "medium",
    health: "on-track",
    progress: 100,
    lead: users[5],
    members: [users[5], users[4], users[2]],
    startDate: "2026-01-15",
    targetDate: "2026-03-30",
    repo: "WEB",
  },
  {
    id: "p8",
    key: "OPS-027",
    name: "Onboarding playbook",
    status: "planned",
    priority: "low",
    health: "no-update",
    progress: 0,
    lead: users[7],
    members: [users[7]],
    targetDate: "2026-09-15",
    repo: "OPS",
  },
  {
    id: "p9",
    key: "API-230",
    name: "Permissions overhaul",
    status: "backlog",
    priority: "high",
    health: "no-update",
    progress: 0,
    lead: users[1],
    members: [users[1], users[3], users[6]],
    targetDate: "2026-09-30",
    repo: "API",
  },
  {
    id: "p10",
    key: "SYM-112",
    name: "Empty-state illustrations",
    status: "completed",
    priority: "low",
    health: "on-track",
    progress: 100,
    lead: users[0],
    members: [users[0], users[5]],
    startDate: "2026-02-01",
    targetDate: "2026-03-12",
    repo: "SYM",
  },
  {
    id: "p11",
    key: "OPS-031",
    name: "Internal status page",
    status: "cancelled",
    priority: "no-priority",
    health: "no-update",
    progress: 18,
    lead: users[7],
    members: [users[7], users[2]],
    targetDate: "2026-04-20",
    repo: "OPS",
  },
  {
    id: "p12",
    key: "API-241",
    name: "Search relevance tuning",
    status: "in-progress",
    priority: "medium",
    health: "on-track",
    progress: 55,
    lead: users[6],
    members: [users[6], users[1]],
    startDate: "2026-04-12",
    targetDate: "2026-06-02",
    repo: "API",
  },
];

export const STATUS_ORDER: ProjectStatus[] = [
  "in-progress",
  "planned",
  "backlog",
  "paused",
  "completed",
  "cancelled",
];

export const STATUS_LABELS: Record<ProjectStatus, string> = {
  backlog: "Backlog",
  planned: "Planned",
  "in-progress": "In Progress",
  paused: "Paused",
  completed: "Completed",
  cancelled: "Cancelled",
};

export const PRIORITY_LABELS: Record<Priority, string> = {
  "no-priority": "No priority",
  urgent: "Urgent",
  high: "High",
  medium: "Medium",
  low: "Low",
};

export const HEALTH_LABELS: Record<Health, string> = {
  "on-track": "On track",
  "at-risk": "At risk",
  "off-track": "Off track",
  "no-update": "No update",
};

// ===== Tasks (formerly "issues") =====

export type TaskStatus =
  | "todo"
  | "in_progress"
  | "in_review"
  | "paused"
  | "completed"
  | "canceled";

export interface Label {
  id: string;
  name: string;
  color: string;
}

export interface Task {
  id: string;
  key: string;
  title: string;
  status: TaskStatus;
  priority: Priority;
  assignee?: User;
  labels: Label[];
  projectId?: string;
  repo: string;
  createdAt: string;
  updatedAt: string;
  dueDate?: string;
}

export const TASK_STATUS_ORDER: TaskStatus[] = [
  "todo",
  "in_progress",
  "in_review",
  "paused",
  "completed",
  "canceled",
];

export const TASK_STATUS_LABELS: Record<TaskStatus, string> = {
  todo: "To-do",
  in_progress: "In Progress",
  in_review: "In Review",
  paused: "Paused",
  completed: "Completed",
  canceled: "Canceled",
};

export const labels: Label[] = [
  { id: "l1", name: "bug", color: "text-red-500" },
  { id: "l2", name: "feature", color: "text-violet-500" },
  { id: "l3", name: "improvement", color: "text-sky-500" },
  { id: "l4", name: "design", color: "text-fuchsia-500" },
  { id: "l5", name: "infra", color: "text-emerald-500" },
  { id: "l6", name: "docs", color: "text-amber-500" },
];

const titles = [
  "Drag handle misaligned on Safari",
  "Add bulk-edit shortcut for selected tasks",
  "Sync hangs when offline for >30s",
  "Timeline view crashes on empty project",
  "Empty state polish for inbox",
  "Permissions: invite-only repositories",
  "Refactor command palette renderer",
  "Add filters by assignee on board",
  "Improve focus ring contrast in dark mode",
  "Markdown paste loses inline code",
  "Webhooks retry queue stalls",
  "Add CSV export for projects",
  "Skeleton loaders flicker on first paint",
  "Notifications grouping by project",
  "Add keyboard shortcut for repository switcher",
  "Search returns archived items",
  "Mobile gestures for swipe-to-archive",
  "Avatar uploader rejects PNGs > 1 MB",
  "Onboarding step 3 copy update",
  "Edge cache misses for project icons",
  "Reorder columns persists per-user",
  "Add 'Snooze' action to inbox",
  "Repository switcher should support search",
  "Cycle burn-up chart renders empty",
  "Add SSO via SAML",
];

const repoKeys = ["SYM", "API", "WEB", "OPS"] as const;
const statuses: TaskStatus[] = [
  "todo",
  "in_progress",
  "in_review",
  "paused",
  "completed",
  "completed",
  "canceled",
];
const priorityCycle: Priority[] = [
  "no-priority",
  "low",
  "medium",
  "medium",
  "high",
  "high",
  "urgent",
];

function pad(n: number, w = 3) {
  return String(n).padStart(w, "0");
}

export const tasks: Task[] = titles.map((title, i) => {
  const repo = repoKeys[i % repoKeys.length];
  const status = statuses[i % statuses.length];
  const priority = priorityCycle[i % priorityCycle.length];
  const assignee = users[i % users.length];
  const ls = [labels[i % labels.length]];
  if (i % 3 === 0) ls.push(labels[(i + 2) % labels.length]);
  const created = new Date(2026, 3, 1 + (i % 28));
  const updated = new Date(2026, 4, 1 + (i % 12));
  return {
    id: `t${i + 1}`,
    key: `${repo}-${pad(120 + i)}`,
    title,
    status,
    priority,
    assignee,
    labels: ls,
    repo,
    projectId: projects[i % projects.length].id,
    createdAt: created.toISOString(),
    updatedAt: updated.toISOString(),
    dueDate: i % 4 === 0 ? new Date(2026, 5, 1 + (i % 28)).toISOString() : undefined,
  };
});

// ===== Member roles =====

export type Role = "Admin" | "Member" | "Guest";

export const userRoles: Record<string, { role: Role; repos: string[]; joined: string }> = {
  u1: { role: "Admin", repos: ["SYM", "WEB"], joined: "2024-09-12" },
  u2: { role: "Member", repos: ["API"], joined: "2025-01-08" },
  u3: { role: "Member", repos: ["SYM"], joined: "2024-11-22" },
  u4: { role: "Admin", repos: ["API", "OPS"], joined: "2024-06-03" },
  u5: { role: "Member", repos: ["WEB"], joined: "2025-03-14" },
  u6: { role: "Guest", repos: ["WEB"], joined: "2025-08-19" },
  u7: { role: "Member", repos: ["API"], joined: "2025-02-02" },
  u8: { role: "Admin", repos: ["OPS"], joined: "2024-10-05" },
};

// ===== Imports (used inside Settings → Integrations) =====

export type ImportSource = "github" | "linear";

export interface ExternalIssue {
  id: string;
  source: ImportSource;
  externalKey: string;
  title: string;
  author: string;
  updatedAt: string;
  repo: string;
  hasConflict?: boolean;
}

export const externalIssues: ExternalIssue[] = [
  {
    id: "ext1",
    source: "github",
    externalKey: "agora-creations/symphonia#412",
    title: "Repository overview should remember selected view",
    author: "alvy-singer",
    updatedAt: "2026-05-19",
    repo: "SYM",
  },
  {
    id: "ext2",
    source: "github",
    externalKey: "agora-creations/api#188",
    title: "Add idempotency key to /tasks POST",
    author: "noah-b",
    updatedAt: "2026-05-18",
    repo: "API",
  },
  {
    id: "ext3",
    source: "linear",
    externalKey: "SYM-441",
    title: "Briefs need an explicit Acceptance criteria section",
    author: "Ava Martinez",
    updatedAt: "2026-05-21",
    repo: "SYM",
    hasConflict: true,
  },
  {
    id: "ext4",
    source: "linear",
    externalKey: "API-202",
    title: "Permissions: invite-only repositories",
    author: "Mira Khan",
    updatedAt: "2026-05-15",
    repo: "API",
  },
  {
    id: "ext5",
    source: "github",
    externalKey: "agora-creations/web#77",
    title: "Marketing site CTA copy is inconsistent",
    author: "sienna",
    updatedAt: "2026-05-12",
    repo: "WEB",
  },
];
