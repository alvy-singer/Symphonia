"use client";

import { useMemo, useState } from "react";
import { cn } from "@/lib/utils";
import { users, projects } from "@/data/mock";
import {
  AtSign,
  MessageSquare,
  GitPullRequest,
  CheckCircle2,
  AlertCircle,
  Bell,
  Inbox as InboxIcon,
  Archive,
  Star,
} from "lucide-react";

type Category = "all" | "mentions" | "assigned" | "subscribed";

interface Notification {
  id: string;
  type: "mention" | "comment" | "assigned" | "status" | "review";
  actor: (typeof users)[number];
  title: string;
  preview: string;
  target: string;
  time: string;
  read: boolean;
  starred?: boolean;
  category: Exclude<Category, "all">[];
  repo: string;
}

const iconFor: Record<Notification["type"], typeof AtSign> = {
  mention: AtSign,
  comment: MessageSquare,
  assigned: CheckCircle2,
  status: AlertCircle,
  review: GitPullRequest,
};

const colorFor: Record<Notification["type"], string> = {
  mention: "text-violet-500",
  comment: "text-sky-500",
  assigned: "text-emerald-500",
  status: "text-amber-500",
  review: "text-fuchsia-500",
};

const allNotifications: Notification[] = [
  {
    id: "n1",
    type: "mention",
    actor: users[1],
    title: `mentioned you in ${projects[0].name}`,
    preview: "@ava can you review the empty state copy before Friday?",
    target: projects[0].key,
    time: "12m",
    read: false,
    category: ["mentions"],
    repo: "SYM",
  },
  {
    id: "n2",
    type: "assigned",
    actor: users[3],
    title: "assigned a task to you",
    preview: "API-482 · Investigate flaky websocket reconnect on mobile",
    target: "API-482",
    time: "1h",
    read: false,
    starred: true,
    category: ["assigned"],
    repo: "API",
  },
  {
    id: "n3",
    type: "review",
    actor: users[2],
    title: "requested your review on a run summary",
    preview: "Codex completed SYM-141 — ready for your review.",
    target: "SYM-141",
    time: "3h",
    read: false,
    category: ["mentions", "subscribed"],
    repo: "SYM",
  },
  {
    id: "n4",
    type: "comment",
    actor: users[4],
    title: `commented on ${projects[1].name}`,
    preview: "Pushed a new spec — milestone dates have shifted by a week.",
    target: projects[1].key,
    time: "5h",
    read: true,
    category: ["subscribed"],
    repo: "API",
  },
  {
    id: "n5",
    type: "status",
    actor: users[5],
    title: "moved a task to In Review",
    preview: "WEB-117 · Component tokens audit",
    target: "WEB-117",
    time: "Yesterday",
    read: true,
    category: ["assigned", "subscribed"],
    repo: "WEB",
  },
  {
    id: "n6",
    type: "mention",
    actor: users[6],
    title: "mentioned you in a thread",
    preview: "Worth syncing with @ava on the Q3 roadmap before Monday.",
    target: "Roadmap",
    time: "Yesterday",
    read: true,
    category: ["mentions"],
    repo: "SYM",
  },
  {
    id: "n7",
    type: "comment",
    actor: users[7],
    title: `commented on ${projects[2]?.name ?? "a project"}`,
    preview: "Updated the launch checklist — three items still open.",
    target: projects[2]?.key ?? "—",
    time: "2d",
    read: true,
    category: ["subscribed"],
    repo: "WEB",
  },
];

const tabs: { id: Category; label: string }[] = [
  { id: "all", label: "All" },
  { id: "mentions", label: "Mentions" },
  { id: "assigned", label: "Assigned" },
  { id: "subscribed", label: "Subscribed" },
];

export function InboxView({ repoKey }: { repoKey: string }) {
  const scoped = useMemo(
    () => allNotifications.filter((n) => n.repo === repoKey),
    [repoKey],
  );
  const [category, setCategory] = useState<Category>("all");
  const [activeId, setActiveId] = useState<string | null>(scoped[0]?.id ?? null);
  const [readMap, setReadMap] = useState<Record<string, boolean>>(
    Object.fromEntries(scoped.map((n) => [n.id, n.read])),
  );

  const filtered = scoped.filter((n) =>
    category === "all" ? true : n.category.includes(category as Exclude<Category, "all">),
  );
  const unread = scoped.filter((n) => !readMap[n.id]).length;
  const active = scoped.find((n) => n.id === activeId) ?? filtered[0];

  const markAllRead = () =>
    setReadMap((m) => Object.fromEntries(Object.keys(m).map((k) => [k, true])));

  return (
    <div className="flex h-full flex-col">
      <header className="flex flex-wrap items-center justify-between gap-2 border-b px-4 py-2.5">
        <div className="flex items-center gap-2">
          <InboxIcon className="h-4 w-4 text-muted-foreground" />
          <span className="text-sm font-semibold">Inbox</span>
          {unread > 0 && (
            <span className="rounded-full bg-primary/10 px-1.5 py-0.5 text-[10px] font-medium text-primary">
              {unread} new
            </span>
          )}
        </div>
        <button
          onClick={markAllRead}
          className="text-xs text-muted-foreground hover:text-foreground transition-colors"
        >
          Mark all as read
        </button>
      </header>

      <div className="flex items-center gap-1 border-b px-3 py-1.5 overflow-x-auto">
        {tabs.map((t) => (
          <button
            key={t.id}
            onClick={() => setCategory(t.id)}
            className={cn(
              "rounded-md px-2.5 py-1 text-xs transition-colors whitespace-nowrap",
              category === t.id
                ? "bg-accent text-foreground font-medium"
                : "text-muted-foreground hover:bg-accent/60 hover:text-foreground",
            )}
          >
            {t.label}
          </button>
        ))}
      </div>

      <div className="flex flex-1 min-h-0">
        <ul className="w-full md:w-[360px] shrink-0 overflow-y-auto border-r divide-y">
          {filtered.length === 0 && (
            <li className="p-6 text-center text-xs text-muted-foreground">
              You&apos;re all caught up.
            </li>
          )}
          {filtered.map((n) => {
            const Icon = iconFor[n.type];
            const isActive = active?.id === n.id;
            const isRead = readMap[n.id];
            return (
              <li key={n.id}>
                <button
                  onClick={() => {
                    setActiveId(n.id);
                    setReadMap((m) => ({ ...m, [n.id]: true }));
                  }}
                  className={cn(
                    "w-full text-left px-3 py-2.5 flex gap-3 transition-colors",
                    isActive ? "bg-accent" : "hover:bg-accent/50",
                  )}
                >
                  <div className="relative shrink-0">
                    <span
                      className={cn(
                        "grid h-7 w-7 place-items-center rounded-full text-[10px] font-medium text-white",
                        n.actor.color,
                      )}
                    >
                      {n.actor.initials}
                    </span>
                    <span className="absolute -bottom-0.5 -right-0.5 grid h-4 w-4 place-items-center rounded-full bg-background border">
                      <Icon className={cn("h-2.5 w-2.5", colorFor[n.type])} />
                    </span>
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      {!isRead && (
                        <span className="h-1.5 w-1.5 rounded-full bg-primary shrink-0" />
                      )}
                      <span
                        className={cn(
                          "text-xs truncate",
                          isRead ? "text-muted-foreground" : "font-medium",
                        )}
                      >
                        <span className="text-foreground">{n.actor.name}</span>{" "}
                        <span className="text-muted-foreground">{n.title}</span>
                      </span>
                    </div>
                    <p className="mt-0.5 text-xs text-muted-foreground line-clamp-2">
                      {n.preview}
                    </p>
                    <div className="mt-1 flex items-center gap-2 text-[10px] text-muted-foreground">
                      <span className="rounded bg-muted px-1.5 py-0.5 font-mono">{n.target}</span>
                      <span>{n.time}</span>
                    </div>
                  </div>
                </button>
              </li>
            );
          })}
        </ul>

        <section className="hidden md:flex flex-1 flex-col">
          {active ? (
            <>
              <div className="flex items-center justify-between border-b px-4 py-2.5">
                <div className="flex items-center gap-2 min-w-0">
                  <span
                    className={cn(
                      "grid h-7 w-7 place-items-center rounded-full text-[10px] font-medium text-white shrink-0",
                      active.actor.color,
                    )}
                  >
                    {active.actor.initials}
                  </span>
                  <div className="min-w-0">
                    <div className="text-sm font-medium truncate">{active.actor.name}</div>
                    <div className="text-xs text-muted-foreground truncate">{active.title}</div>
                  </div>
                </div>
                <div className="flex items-center gap-1">
                  <button
                    aria-label="Star"
                    className="grid h-7 w-7 place-items-center rounded-md hover:bg-accent text-muted-foreground"
                  >
                    <Star
                      className={cn(
                        "h-3.5 w-3.5",
                        active.starred && "fill-amber-500 text-amber-500",
                      )}
                    />
                  </button>
                  <button
                    aria-label="Subscribe"
                    className="grid h-7 w-7 place-items-center rounded-md hover:bg-accent text-muted-foreground"
                  >
                    <Bell className="h-3.5 w-3.5" />
                  </button>
                  <button
                    aria-label="Archive"
                    className="grid h-7 w-7 place-items-center rounded-md hover:bg-accent text-muted-foreground"
                  >
                    <Archive className="h-3.5 w-3.5" />
                  </button>
                </div>
              </div>
              <div className="flex-1 overflow-y-auto p-6">
                <div className="mb-3 flex items-center gap-2">
                  <span className="rounded bg-muted px-2 py-0.5 text-[11px] font-mono">
                    {active.target}
                  </span>
                  <span className="text-[11px] text-muted-foreground">{active.time} ago</span>
                </div>
                <p className="text-sm leading-relaxed">{active.preview}</p>
                <div className="mt-6 rounded-md border bg-muted/30 p-3 text-xs text-muted-foreground">
                  Reply, react, or open the linked work item to continue the thread.
                </div>
              </div>
            </>
          ) : (
            <div className="flex flex-1 items-center justify-center text-sm text-muted-foreground">
              Select a notification
            </div>
          )}
        </section>
      </div>
    </div>
  );
}
