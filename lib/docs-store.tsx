"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";

/**
 * Notion-like document store for Symphonía.
 *
 * Every durable workspace object (Task brief, Project page, Doc, Decision,
 * Review, Run Summary, plus root automation rules) lives here as a Markdown-backed
 * page with a stable repo file path. Paths follow the configurable doc root:
 *
 *   symphonia/projects/<id>.md
 *   symphonia/tasks/<key>.md
 *   symphonia/docs/<slug>.md  (can be nested)
 *   symphonia/decisions/<slug>.md
 *   symphonia/reviews/<slug>.md
 *   symphonia/run-summaries/<slug>.md
 *
 * Workflow is the single exception and lives at the repository root.
 *
 * Local-first: pages are kept in React state and mirrored to localStorage so
 * the prototype survives reloads. The "repository file" is the conceptual
 * source of truth — the store models that contract.
 */

export type DocCategory =
  | "task"
  | "project"
  | "doc"
  | "decision"
  | "review"
  | "run-summary"
  | "workflow";

export interface DocPage {
  id: string;
  repo: string;
  category: DocCategory;
  /** Repo-relative file path, e.g. "symphonia/docs/architecture.md". */
  path: string;
  title: string;
  body: string;
  icon?: string; // emoji
  cover?: string; // gradient id
  parentId?: string;
  /** Free-form linked sources for tasks (URLs, issue refs). */
  links?: string[];
  /** Task-specific metadata, opaque to the editor. */
  meta?: Record<string, string | number | boolean | undefined>;
  createdAt: number;
  updatedAt: number;
}

export const CATEGORY_LABELS: Record<DocCategory, string> = {
  task: "Tasks",
  project: "Projects",
  doc: "Docs",
  decision: "Decisions",
  review: "Reviews",
  "run-summary": "Run Summaries",
  workflow: "Workflow",
};

export const CATEGORY_SINGULAR: Record<DocCategory, string> = {
  task: "Task",
  project: "Project",
  doc: "Doc",
  decision: "Decision",
  review: "Review",
  "run-summary": "Run Summary",
  workflow: "Workflow",
};

export const COVERS = [
  { id: "sunset", className: "bg-gradient-to-br from-amber-300 via-rose-400 to-fuchsia-500" },
  { id: "ocean", className: "bg-gradient-to-br from-sky-400 via-cyan-500 to-emerald-500" },
  { id: "forest", className: "bg-gradient-to-br from-emerald-500 via-teal-500 to-cyan-600" },
  { id: "violet", className: "bg-gradient-to-br from-violet-500 via-fuchsia-500 to-rose-500" },
  { id: "graphite", className: "bg-gradient-to-br from-zinc-700 via-zinc-800 to-zinc-900" },
  { id: "paper", className: "bg-gradient-to-br from-stone-200 via-stone-100 to-amber-100" },
];

export const COMMON_ICONS = [
  "📄", "📘", "📝", "🧭", "🗺️", "🏗️", "🎯", "🧩", "⚙️", "🔒",
  "🚀", "🔭", "🪲", "✨", "🧪", "📐", "🛠️", "🧱", "📊", "🪪",
];

const STORAGE_KEY = "symphonia.docs.v1";

function pathFor(category: DocCategory, slug: string): string {
  if (category === "workflow") return "Automation Rules";
  const folder: Record<Exclude<DocCategory, "workflow">, string> = {
    task: "symphonia/tasks",
    project: "symphonia/projects",
    doc: "symphonia/docs",
    decision: "symphonia/decisions",
    review: "symphonia/reviews",
    "run-summary": "symphonia/run-summaries",
  };
  return `${folder[category as Exclude<DocCategory, "workflow">]}/${slug}.md`;
}

function slugify(s: string): string {
  return (
    s
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 60) || "untitled"
  );
}

function uid(prefix = "p") {
  return `${prefix}_${Math.random().toString(36).slice(2, 9)}_${Date.now().toString(36)}`;
}

/* ---------- Seed pages ---------- */

function buildSeed(): DocPage[] {
  const now = Date.now();
  const repos = ["SYM", "API", "WEB", "OPS"];
  const seeds: DocPage[] = [];

  for (const repo of repos) {
    seeds.push({
      id: uid("wf"),
      repo,
      category: "workflow",
      path: "WORKFLOW" + ".md",
      title: "Automation Rules",
      icon: "🧭",
      body:
        "# Automation rules\n# Simple PR — Clarise runs, opens a PR, human reviews on GitHub.\n\non_task_started:\n  - assign: clarise\n  - require_pr: true\n\non_run_complete:\n  - status: in_review\n  - notify_assignees: true\n\non_pr_merged:\n  - status: completed\n",
      createdAt: now,
      updatedAt: now,
    });

    if (repo === "SYM") {
      const archId = uid("doc");
      seeds.push({
        id: archId,
        repo,
        category: "doc",
        path: "symphonia/docs/architecture.md",
        title: "Architecture",
        icon: "🏗️",
        cover: "graphite",
        body:
          "# Architecture\n\nSymphonía is a Notion-like workspace backed by repositories. " +
          "Every durable object — Task, Project, Doc, Decision, Review, Run Summary, plus " +
          "root automation rules — is canonical Markdown in the repository.\n\n" +
          "## What you are looking at\n\nThis page is a long-form doc in the workspace. " +
          "It edits as Markdown and saves back to `symphonia/docs/architecture.md`.\n\n" +
          "## Why it matters\n\nDocuments are the system of record. GitHub and Linear " +
          "issues are linked projections, never the canonical Task object.\n",
        createdAt: now,
        updatedAt: now,
      });
      seeds.push({
        id: uid("doc"),
        repo,
        category: "doc",
        path: "symphonia/docs/architecture/editor.md",
        title: "Editor model",
        icon: "📝",
        parentId: archId,
        body:
          "# Editor model\n\nThe editor is intentionally Markdown-first. Title, body, " +
          "icon, and cover are stored on the page. Pages can nest. The repository file " +
          "is the source of truth.\n",
        createdAt: now,
        updatedAt: now,
      });
      seeds.push({
        id: uid("doc"),
        repo,
        category: "doc",
        path: "symphonia/docs/onboarding.md",
        title: "Onboarding",
        icon: "🧭",
        cover: "ocean",
        body:
          "# Onboarding\n\nWelcome to Symphonía. This doc walks new contributors through " +
          "the workspace.\n\n- Open Tasks to see work on a board.\n" +
          "- Use Cmd+K (or Ctrl+K) to jump anywhere.\n- Ask Clarise from the bottom-right " +
          "if you want a draft started for you.\n",
        createdAt: now,
        updatedAt: now,
      });
      seeds.push({
        id: uid("dec"),
        repo,
        category: "decision",
        path: "symphonia/decisions/2026-05-markdown-source-of-truth.md",
        title: "Markdown is the source of truth",
        icon: "🪪",
        body:
          "# Markdown is the source of truth\n\n**Status:** Accepted\n\n**Decision.** Tasks, " +
          "Projects, Docs, Decisions, Reviews and Run Summaries are stored as Markdown in " +
          "the repository. GitHub/Linear issues are linked projections only.\n\n" +
          "**Why.** Repo-backed Markdown is durable, diffable, reviewable in PRs, and " +
          "portable across tools.\n",
        createdAt: now,
        updatedAt: now,
      });
      seeds.push({
        id: uid("rev"),
        repo,
        category: "review",
        path: "symphonia/reviews/2026-05-19-overview-redesign.md",
        title: "Tasks redesign - review notes",
        icon: "🔭",
        body:
          "# Tasks redesign - review notes\n\n- Board is the right default; remembering " +
          "the chosen mode per repository feels good.\n- Empty status columns should still " +
          "render so the structure is visible.\n- Card density needs another pass for very " +
          "long titles.\n",
        createdAt: now,
        updatedAt: now,
      });
      seeds.push({
        id: uid("run"),
        repo,
        category: "run-summary",
        path: "symphonia/run-summaries/2026-05-21-clarise-task-cards.md",
        title: "Clarise run - task card density",
        icon: "🚀",
        body:
          "# Clarise run - task card density\n\n**Assistant:** Clarise\n\n" +
          "**Files changed:** 4\n\n**Summary.** Tightened card padding, switched to " +
          "tabular numerals for IDs, and added a 2-line clamp on titles.\n\n" +
          "**Validation.** Tests passed. Lint clean.\n",
        createdAt: now,
        updatedAt: now,
      });
    }
  }

  return seeds;
}

/* ---------- Context ---------- */

interface DocsState {
  pages: DocPage[];
  /** Pages that are open as editable drafts but not yet saved. */
  drafts: DocPage[];
  /** True once the store has loaded any persisted pages from localStorage. */
  hydrated: boolean;
  byId: (id: string) => DocPage | undefined;
  byPath: (repo: string, path: string) => DocPage | undefined;
  forRepo: (repo: string) => DocPage[];
  /** Open a fresh draft for a category (used by "New …" actions). */
  newDraft: (
    repo: string,
    category: DocCategory,
    init?: Partial<Pick<DocPage, "title" | "body" | "icon" | "parentId" | "links" | "meta">>,
  ) => DocPage;
  /** Create a saved page directly (no draft step). Used to promote mock data. */
  createPage: (
    repo: string,
    category: DocCategory,
    init: Partial<Pick<DocPage, "title" | "body" | "icon" | "parentId" | "links" | "meta">>,
  ) => DocPage;
  updateDraft: (id: string, patch: Partial<DocPage>) => void;
  saveDraft: (id: string) => DocPage | undefined;
  discardDraft: (id: string) => void;
  updatePage: (id: string, patch: Partial<DocPage>) => void;
  ensureWorkflow: (repo: string) => DocPage;
}

const Ctx = createContext<DocsState | null>(null);

export function DocsProvider({ children }: { children: ReactNode }) {
  const [pages, setPages] = useState<DocPage[]>([]);
  const [drafts, setDrafts] = useState<DocPage[]>([]);
  const [hydrated, setHydrated] = useState(false);

  // Hydrate from localStorage once on the client.
  useEffect(() => {
    try {
      const raw = typeof window !== "undefined" ? window.localStorage.getItem(STORAGE_KEY) : null;
      if (raw) {
        const parsed = JSON.parse(raw) as DocPage[];
        setPages(parsed);
      } else {
        setPages(buildSeed());
      }
    } catch {
      setPages(buildSeed());
    }
    setHydrated(true);
  }, []);

  // Persist on change.
  useEffect(() => {
    if (!hydrated) return;
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(pages));
    } catch {
      /* ignore quota errors */
    }
  }, [pages, hydrated]);

  const byId = useCallback(
    (id: string) => pages.find((p) => p.id === id) ?? drafts.find((p) => p.id === id),
    [pages, drafts],
  );
  const byPath = useCallback(
    (repo: string, path: string) => pages.find((p) => p.repo === repo && p.path === path),
    [pages],
  );
  const forRepo = useCallback((repo: string) => pages.filter((p) => p.repo === repo), [pages]);

  const newDraft = useCallback<DocsState["newDraft"]>((repo, category, init) => {
    const now = Date.now();
    const draft: DocPage = {
      id: uid("draft"),
      repo,
      category,
      path: pathFor(category, slugify(init?.title ?? "untitled")),
      title: init?.title ?? "",
      body: init?.body ?? "",
      icon: init?.icon,
      parentId: init?.parentId,
      links: init?.links,
      meta: init?.meta,
      createdAt: now,
      updatedAt: now,
    };
    setDrafts((d) => [...d, draft]);
    return draft;
  }, []);

  const createPage: DocsState["createPage"] = useCallback((repo, category, init) => {
    const now = Date.now();
    const page: DocPage = {
      id: uid("page"),
      repo,
      category,
      path: pathFor(category, slugify(init.title ?? "untitled")),
      title: init.title ?? "",
      body: init.body ?? "",
      icon: init.icon,
      parentId: init.parentId,
      links: init.links,
      meta: init.meta,
      createdAt: now,
      updatedAt: now,
    };
    setPages((p) => [...p, page]);
    return page;
  }, []);

  const updateDraft: DocsState["updateDraft"] = useCallback((id, patch) => {
    setDrafts((d) =>
      d.map((p) => (p.id === id ? { ...p, ...patch, updatedAt: Date.now() } : p)),
    );
  }, []);

  const saveDraft: DocsState["saveDraft"] = useCallback((id) => {
    let saved: DocPage | undefined;
    setDrafts((d) => {
      const found = d.find((p) => p.id === id);
      if (!found) return d;
      // Re-derive a stable path from the final title at save time.
      const path = pathFor(found.category, slugify(found.title || "untitled"));
      saved = { ...found, path, updatedAt: Date.now() };
      return d.filter((p) => p.id !== id);
    });
    if (saved) setPages((p) => [...p, saved!]);
    return saved;
  }, []);

  const discardDraft: DocsState["discardDraft"] = useCallback((id) => {
    setDrafts((d) => d.filter((p) => p.id !== id));
  }, []);

  const updatePage: DocsState["updatePage"] = useCallback((id, patch) => {
    setPages((p) =>
      p.map((page) => (page.id === id ? { ...page, ...patch, updatedAt: Date.now() } : page)),
    );
    setDrafts((d) =>
      d.map((page) => (page.id === id ? { ...page, ...patch, updatedAt: Date.now() } : page)),
    );
  }, []);

  const ensureWorkflow: DocsState["ensureWorkflow"] = useCallback(
    (repo) => {
      const existing = pages.find((p) => p.repo === repo && p.category === "workflow");
      if (existing) return existing;
      const now = Date.now();
      const created: DocPage = {
        id: uid("wf"),
        repo,
        category: "workflow",
        path: "WORKFLOW" + ".md",
        title: "Automation Rules",
        icon: "🧭",
        body: "",
        createdAt: now,
        updatedAt: now,
      };
      setPages((p) => [...p, created]);
      return created;
    },
    [pages],
  );

  const value = useMemo<DocsState>(
    () => ({
      pages,
      drafts,
      hydrated,
      byId,
      byPath,
      forRepo,
      newDraft,
      createPage,
      updateDraft,
      saveDraft,
      discardDraft,
      updatePage,
      ensureWorkflow,
    }),
    [
      pages,
      drafts,
      hydrated,
      byId,
      byPath,
      forRepo,
      newDraft,
      createPage,
      updateDraft,
      saveDraft,
      discardDraft,
      updatePage,
      ensureWorkflow,
    ],
  );

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useDocs(): DocsState {
  const v = useContext(Ctx);
  if (!v) throw new Error("useDocs must be used inside <DocsProvider>");
  return v;
}

export { pathFor, slugify };
