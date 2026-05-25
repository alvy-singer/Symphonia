"use client";

import { useMemo, useState } from "react";
import {
  ChevronDown,
  Filter,
  SlidersHorizontal,
  Plus,
  Calendar,
  X,
  List,
  LayoutGrid,
  Columns3,
  Check,
} from "lucide-react";
import {
  projects as allProjects,
  STATUS_ORDER,
  STATUS_LABELS,
  PRIORITY_LABELS,
  HEALTH_LABELS,
  type Project,
  type ProjectStatus,
  type Priority,
  type Health,
} from "@/data/mock";
import {
  StatusIcon,
  PriorityIcon,
  HealthDot,
  ProgressRing,
} from "@/components/icons/status-icons";
import { AvatarStack, UserAvatar } from "@/components/avatar-stack";
import { Popover, PopoverTrigger, PopoverContent } from "@/components/ui/popover";
import { cn } from "@/lib/utils";

type GroupBy = "status" | "priority" | "health" | "none";
type Layout = "list" | "board" | "grid";
type OrderBy = "manual" | "priority" | "name" | "target" | "progress";
type PropertyKey = "priority" | "health" | "target" | "progress" | "members";

function fmtDate(iso?: string) {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

function ProjectRow({
  p,
  props,
}: {
  p: Project;
  props: Record<PropertyKey, boolean>;
}) {
  return (
    <div className="group grid grid-cols-[1.5rem_1fr_auto] items-center gap-3 px-4 py-2 border-b last:border-b-0 hover:bg-muted/40 transition-colors cursor-pointer">
      <StatusIcon status={p.status} />
      <div className="flex items-center gap-2 min-w-0">
        <span className="text-[11px] tabular-nums text-muted-foreground shrink-0 w-16">
          {p.key}
        </span>
        <span className="text-sm font-medium truncate">{p.name}</span>
        {props.health && (
          <div className="flex items-center gap-1 ml-2 shrink-0">
            <HealthDot health={p.health} />
            <span className="text-[11px] text-muted-foreground hidden md:inline">
              {HEALTH_LABELS[p.health]}
            </span>
          </div>
        )}
      </div>
      <div className="flex items-center gap-3 shrink-0">
        {props.priority && (
          <div className="hidden md:flex items-center gap-1.5 text-[11px] text-muted-foreground">
            <PriorityIcon priority={p.priority} />
            <span className="hidden lg:inline">{PRIORITY_LABELS[p.priority]}</span>
          </div>
        )}
        {props.target && (
          <div className="hidden lg:flex items-center gap-1.5 text-[11px] text-muted-foreground tabular-nums w-20">
            <Calendar className="h-3 w-3" />
            {fmtDate(p.targetDate)}
          </div>
        )}
        {props.progress && (
          <div className="hidden md:flex items-center gap-1.5 w-16">
            <ProgressRing value={p.progress} />
            <span className="text-[11px] tabular-nums text-muted-foreground">
              {p.progress}%
            </span>
          </div>
        )}
        {props.members && (
          <>
            <div className="hidden sm:block">
              <AvatarStack users={p.members} max={3} size={20} />
            </div>
            <UserAvatar user={p.lead} size={20} className="sm:hidden" />
          </>
        )}
      </div>
    </div>
  );
}

function ProjectCard({
  p,
  props,
}: {
  p: Project;
  props: Record<PropertyKey, boolean>;
}) {
  return (
    <div className="rounded-lg border bg-card p-3 hover:bg-muted/40 transition-colors cursor-pointer space-y-2">
      <div className="flex items-center gap-2">
        <StatusIcon status={p.status} />
        <span className="text-[11px] tabular-nums text-muted-foreground">{p.key}</span>
        {props.health && <HealthDot health={p.health} />}
      </div>
      <div className="text-sm font-medium leading-snug line-clamp-2">{p.name}</div>
      <div className="flex items-center justify-between gap-2 pt-1">
        <div className="flex items-center gap-2 text-[11px] text-muted-foreground">
          {props.priority && <PriorityIcon priority={p.priority} />}
          {props.target && (
            <span className="inline-flex items-center gap-1 tabular-nums">
              <Calendar className="h-3 w-3" />
              {fmtDate(p.targetDate)}
            </span>
          )}
          {props.progress && (
            <span className="inline-flex items-center gap-1">
              <ProgressRing value={p.progress} />
              <span className="tabular-nums">{p.progress}%</span>
            </span>
          )}
        </div>
        {props.members && <AvatarStack users={p.members} max={3} size={18} />}
      </div>
    </div>
  );
}

const PRIORITIES: Priority[] = ["urgent", "high", "medium", "low", "no-priority"];
const HEALTHS: Health[] = ["on-track", "at-risk", "off-track", "no-update"];

function Chip({
  label,
  onClear,
}: {
  label: string;
  onClear?: () => void;
}) {
  return (
    <span className="inline-flex items-center gap-1 rounded-full border bg-muted/50 px-2 py-0.5 text-[11px]">
      {label}
      {onClear && (
        <button
          aria-label={`Clear ${label}`}
          onClick={onClear}
          className="text-muted-foreground hover:text-foreground"
        >
          <X className="h-3 w-3" />
        </button>
      )}
    </span>
  );
}

const DEFAULT_PROPS: Record<PropertyKey, boolean> = {
  priority: true,
  health: true,
  target: true,
  progress: true,
  members: true,
};

const PROPERTY_LABELS: Record<PropertyKey, string> = {
  priority: "Priority",
  health: "Health",
  target: "Target date",
  progress: "Progress",
  members: "Members",
};

const ORDER_LABELS: Record<OrderBy, string> = {
  manual: "Manual",
  priority: "Priority",
  name: "Name",
  target: "Target date",
  progress: "Progress",
};

const GROUP_LABELS: Record<GroupBy, string> = {
  status: "Status",
  priority: "Priority",
  health: "Health",
  none: "No grouping",
};

const PRIORITY_RANK: Record<Priority, number> = {
  urgent: 0,
  high: 1,
  medium: 2,
  low: 3,
  "no-priority": 4,
};

function sortProjects(list: Project[], orderBy: OrderBy): Project[] {
  if (orderBy === "manual") return list;
  const arr = [...list];
  arr.sort((a, b) => {
    switch (orderBy) {
      case "priority":
        return PRIORITY_RANK[a.priority] - PRIORITY_RANK[b.priority];
      case "name":
        return a.name.localeCompare(b.name);
      case "target":
        return (a.targetDate ?? "9999").localeCompare(b.targetDate ?? "9999");
      case "progress":
        return b.progress - a.progress;
    }
    return 0;
  });
  return arr;
}

function DisplayMenu({
  layout,
  setLayout,
  groupBy,
  setGroupBy,
  orderBy,
  setOrderBy,
  properties,
  setProperties,
  onReset,
}: {
  layout: Layout;
  setLayout: (l: Layout) => void;
  groupBy: GroupBy;
  setGroupBy: (g: GroupBy) => void;
  orderBy: OrderBy;
  setOrderBy: (o: OrderBy) => void;
  properties: Record<PropertyKey, boolean>;
  setProperties: (p: Record<PropertyKey, boolean>) => void;
  onReset: () => void;
}) {
  const layoutOpts: { value: Layout; label: string; icon: typeof List }[] = [
    { value: "list", label: "List", icon: List },
    { value: "board", label: "Board", icon: Columns3 },
    { value: "grid", label: "Grid", icon: LayoutGrid },
  ];
  return (
    <div className="w-72 p-3 space-y-3 text-sm">
      <div>
        <div className="text-[11px] font-medium uppercase tracking-wider text-muted-foreground mb-1.5">
          Layout
        </div>
        <div className="grid grid-cols-3 gap-1">
          {layoutOpts.map((o) => {
            const Icon = o.icon;
            const active = layout === o.value;
            return (
              <button
                key={o.value}
                onClick={() => setLayout(o.value)}
                className={cn(
                  "flex flex-col items-center gap-1 rounded-md border px-2 py-2 text-[11px] transition-colors",
                  active
                    ? "border-primary bg-primary/10 text-foreground"
                    : "hover:bg-muted text-muted-foreground",
                )}
              >
                <Icon className="h-4 w-4" />
                {o.label}
              </button>
            );
          })}
        </div>
      </div>

      <SelectRow
        label="Grouping"
        value={groupBy}
        onChange={(v) => setGroupBy(v as GroupBy)}
        options={(Object.keys(GROUP_LABELS) as GroupBy[]).map((k) => ({
          value: k,
          label: GROUP_LABELS[k],
        }))}
      />

      <SelectRow
        label="Ordering"
        value={orderBy}
        onChange={(v) => setOrderBy(v as OrderBy)}
        options={(Object.keys(ORDER_LABELS) as OrderBy[]).map((k) => ({
          value: k,
          label: ORDER_LABELS[k],
        }))}
      />

      <div>
        <div className="text-[11px] font-medium uppercase tracking-wider text-muted-foreground mb-1.5">
          Properties
        </div>
        <div className="space-y-0.5">
          {(Object.keys(PROPERTY_LABELS) as PropertyKey[]).map((k) => (
            <button
              key={k}
              onClick={() =>
                setProperties({ ...properties, [k]: !properties[k] })
              }
              className="w-full flex items-center justify-between rounded px-2 py-1 hover:bg-muted text-left"
            >
              <span>{PROPERTY_LABELS[k]}</span>
              {properties[k] && <Check className="h-3.5 w-3.5 text-primary" />}
            </button>
          ))}
        </div>
      </div>

      <button
        onClick={onReset}
        className="w-full rounded-md border px-2 py-1 text-[12px] text-muted-foreground hover:bg-muted hover:text-foreground"
      >
        Reset to default
      </button>
    </div>
  );
}

function SelectRow({
  label,
  value,
  onChange,
  options,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  options: { value: string; label: string }[];
}) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-[12px] text-muted-foreground">{label}</span>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        aria-label={label}
        className="rounded-md border bg-background px-2 py-1 text-[12px]"
      >
        {options.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    </div>
  );
}

export function ProjectsView({ repoKey }: { repoKey: string }) {
  const [groupBy, setGroupBy] = useState<GroupBy>("status");
  const [priority, setPriority] = useState<Priority | "all">("all");
  const [health, setHealth] = useState<Health | "all">("all");
  const [openMap, setOpenMap] = useState<Record<string, boolean>>({});
  const [layout, setLayout] = useState<Layout>("list");
  const [orderBy, setOrderBy] = useState<OrderBy>("manual");
  const [properties, setProperties] =
    useState<Record<PropertyKey, boolean>>(DEFAULT_PROPS);

  const filtered = useMemo(
    () =>
      allProjects.filter(
        (p) =>
          p.repo === repoKey &&
          (priority === "all" || p.priority === priority) &&
          (health === "all" || p.health === health),
      ),
    [repoKey, priority, health],
  );

  const { groupKeys, grouped, label } = useMemo(() => {
    const sorted = sortProjects(filtered, orderBy);
    if (groupBy === "none") {
      return {
        groupKeys: ["all"] as readonly string[],
        grouped: { all: sorted } as Record<string, Project[]>,
        label: () => "All projects",
      };
    }
    if (groupBy === "status") {
      const m = {} as Record<string, Project[]>;
      for (const s of STATUS_ORDER) m[s] = [];
      for (const p of sorted) m[p.status].push(p);
      return {
        groupKeys: STATUS_ORDER as readonly string[],
        grouped: m,
        label: (k: string) => STATUS_LABELS[k as ProjectStatus],
      };
    }
    if (groupBy === "priority") {
      const m: Record<string, Project[]> = {};
      for (const pr of PRIORITIES) m[pr] = [];
      for (const p of sorted) m[p.priority].push(p);
      return {
        groupKeys: PRIORITIES,
        grouped: m,
        label: (k: string) => PRIORITY_LABELS[k as Priority],
      };
    }
    const m: Record<string, Project[]> = {};
    for (const h of HEALTHS) m[h] = [];
    for (const p of sorted) m[p.health].push(p);
    return {
      groupKeys: HEALTHS,
      grouped: m,
      label: (k: string) => HEALTH_LABELS[k as Health],
    };
  }, [filtered, groupBy, orderBy]);

  const isOpen = (k: string) => openMap[k] !== false;
  const toggle = (k: string) => setOpenMap((m) => ({ ...m, [k]: !isOpen(k) }));

  const activeFilters: { label: string; clear: () => void }[] = [];
  if (priority !== "all")
    activeFilters.push({
      label: `Priority: ${PRIORITY_LABELS[priority]}`,
      clear: () => setPriority("all"),
    });
  if (health !== "all")
    activeFilters.push({
      label: `Health: ${HEALTH_LABELS[health]}`,
      clear: () => setHealth("all"),
    });

  const resetDisplay = () => {
    setLayout("list");
    setGroupBy("status");
    setOrderBy("manual");
    setProperties(DEFAULT_PROPS);
  };

  const renderGroupContent = (list: Project[]) => {
    if (layout === "board") {
      return (
        <div className="flex gap-2 p-3 overflow-x-auto">
          {list.map((p) => (
            <div key={p.id} className="w-64 shrink-0">
              <ProjectCard p={p} props={properties} />
            </div>
          ))}
        </div>
      );
    }
    if (layout === "grid") {
      return (
        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-2 p-3">
          {list.map((p) => (
            <ProjectCard key={p.id} p={p} props={properties} />
          ))}
        </div>
      );
    }
    return (
      <div>
        {list.map((p) => (
          <ProjectRow key={p.id} p={p} props={properties} />
        ))}
      </div>
    );
  };

  return (
    <div className="flex h-full flex-col">
      <header className="flex flex-wrap items-center justify-between gap-3 border-b px-4 py-2.5">
        <div className="flex items-center gap-2 text-sm">
          <span className="font-semibold">Projects</span>
          <span className="text-muted-foreground tabular-nums">{filtered.length}</span>
        </div>
        <div className="flex items-center gap-1">
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
          <select
            value={health}
            onChange={(e) => setHealth(e.target.value as Health | "all")}
            aria-label="Filter by health"
            className="rounded-md border bg-background px-2 py-1 text-[12px]"
          >
            <option value="all">All health</option>
            {HEALTHS.map((h) => (
              <option key={h} value={h}>
                {HEALTH_LABELS[h]}
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
          <Popover>
            <PopoverTrigger asChild>
              <button className="inline-flex items-center gap-1.5 rounded-md border px-2 py-1 text-[12px] hover:bg-muted">
                <SlidersHorizontal className="h-3.5 w-3.5" /> Display
              </button>
            </PopoverTrigger>
            <PopoverContent align="end" className="p-0 w-auto">
              <DisplayMenu
                layout={layout}
                setLayout={setLayout}
                groupBy={groupBy}
                setGroupBy={setGroupBy}
                orderBy={orderBy}
                setOrderBy={setOrderBy}
                properties={properties}
                setProperties={setProperties}
                onReset={resetDisplay}
              />
            </PopoverContent>
          </Popover>
          <button
            disabled
            title="Coming soon"
            className="inline-flex cursor-not-allowed items-center gap-1.5 rounded-md bg-primary px-2 py-1 text-[12px] text-primary-foreground opacity-60"
          >
            <Plus className="h-3.5 w-3.5" /> New project
          </button>
        </div>
      </header>

      {activeFilters.length > 0 && (
        <div className="flex flex-wrap items-center gap-2 border-b px-4 py-2">
          {activeFilters.map((f) => (
            <Chip key={f.label} label={f.label} onClear={f.clear} />
          ))}
          <button
            onClick={() => {
              setPriority("all");
              setHealth("all");
            }}
            className="text-[11px] text-muted-foreground hover:text-foreground"
          >
            Clear all
          </button>
        </div>
      )}

      <div className="flex-1 overflow-auto">
        {groupKeys.map((k) => {
          const list = grouped[k] ?? [];
          if (list.length === 0) return null;
          const open = isOpen(k);
          return (
            <section key={k} className="border-b last:border-b-0">
              <button
                onClick={() => toggle(k)}
                className="w-full flex items-center gap-2 px-4 py-2 bg-muted/30 hover:bg-muted/50 transition-colors text-left"
              >
                <ChevronDown
                  className={cn(
                    "h-3.5 w-3.5 text-muted-foreground transition-transform",
                    !open && "-rotate-90",
                  )}
                />
                {groupBy === "status" && <StatusIcon status={k as ProjectStatus} />}
                {groupBy === "priority" && <PriorityIcon priority={k as Priority} />}
                {groupBy === "health" && <HealthDot health={k as Health} />}
                <span className="text-sm font-medium">{label(k)}</span>
                <span className="text-[11px] text-muted-foreground tabular-nums">
                  {list.length}
                </span>
              </button>
              {open && renderGroupContent(list)}
            </section>
          );
        })}
        {filtered.length === 0 && (
          <div className="p-12 text-center text-sm text-muted-foreground">
            No projects in this repository yet.
          </div>
        )}
      </div>
    </div>
  );
}
