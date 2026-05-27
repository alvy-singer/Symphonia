"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { usePathname, useRouter } from "next/navigation";
import { Sparkles, Send, X, FilePlus2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { CATEGORY_SINGULAR, type DocCategory } from "@/lib/docs-store";
import { useDraftHost } from "@/components/draft-host";
import { useNewTask } from "@/components/new-task-dialog";

interface Message {
  id: string;
  role: "user" | "clarise";
  content: string;
  /** If set, this message can be saved as a new draft of the given category. */
  saveable?:
    | { category: DocCategory; suggestedTitle: string }
    | {
        specAction: "starter_codebase_map" | "starter_milestone" | "decision_record";
        suggestedTitle: string;
      };
}

const SUGGESTIONS = [
  "Draft a task brief for the next priority",
  "Draft acceptance criteria from these notes",
  "Summarize the latest run on this task",
  "Draft a decision: repository documents are the source of truth",
];

interface ClariseCtxValue {
  open: () => void;
}
const ClariseCtx = createContext<ClariseCtxValue>({ open: () => {} });
export const useClarise = () => useContext(ClariseCtx);

/**
 * ClariseProvider exposes the open() handle so the command palette can ask
 * Clarise to open. It also reacts to an external "askPing" counter so a
 * different parent (the layout) can request Clarise to surface.
 */
export function ClariseProvider({
  children,
  askPing,
}: {
  children: ReactNode;
  askPing?: number;
}) {
  const [openSignal, setOpenSignal] = useState(0);
  useEffect(() => {
    if (askPing && askPing > 0) setOpenSignal((s) => s + 1);
  }, [askPing]);

  const open = useCallback(() => setOpenSignal((s) => s + 1), []);
  return <ClariseCtx.Provider value={{ open }}>{
    // The actual Clarise component reads `openSignal` via context below.
    <ClariseSignalBridge openSignal={openSignal}>{children}</ClariseSignalBridge>
  }</ClariseCtx.Provider>;
}

const SignalCtx = createContext<{ openSignal: number }>({ openSignal: 0 });
function ClariseSignalBridge({
  openSignal,
  children,
}: {
  openSignal: number;
  children: ReactNode;
}) {
  return <SignalCtx.Provider value={{ openSignal }}>{children}</SignalCtx.Provider>;
}

export function Clarise({ repoKey }: { repoKey: string }) {
  const [open, setOpen] = useState(false);
  const [messages, setMessages] = useState<Message[]>([
    {
      id: "m0",
      role: "clarise",
      content: `Hi — I'm Clarise. I can help draft starter codebase maps, milestones, decisions, requirements, plans, tasks, reviews, run summaries, or repository rules for ${repoKey}.`,
    },
  ]);
  const [draft, setDraft] = useState("");
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const { startDraft } = useDraftHost();
  const newTask = useNewTask();
  const { openSignal } = useContext(SignalCtx);
  const router = useRouter();
  const pathname = usePathname();
  const isRepoHome = pathname === `/r/${repoKey.toLowerCase()}`;

  // Route existing Clarise entry points into the full-page private workspace chat.
  useEffect(() => {
    if (openSignal > 0) router.push(`/r/${repoKey.toLowerCase()}`);
  }, [openSignal, repoKey, router]);

  useEffect(() => {
    if (open) inputRef.current?.focus();
  }, [open]);

  useEffect(() => {
    listRef.current?.scrollTo({ top: listRef.current.scrollHeight });
  }, [messages, open]);

  const send = (text: string) => {
    const trimmed = text.trim();
    if (!trimmed) return;
    const userMsg: Message = { id: `u${Date.now()}`, role: "user", content: trimmed };
    setMessages((m) => [...m, userMsg]);
    setDraft("");
    setTimeout(() => {
      const reply = respond(trimmed, repoKey);
      setMessages((m) => [...m, { id: `c${Date.now()}`, role: "clarise", ...reply }]);
    }, 350);
  };

  const handleSaveAsDraft = async (
    msg: Message,
    overrideCategory?: DocCategory,
  ) => {
    if (!msg.saveable) return;
    if ("specAction" in msg.saveable && !overrideCategory) {
      try {
        const artifact = await createSpecArtifact(repoKey, msg.saveable.specAction, msg.saveable.suggestedTitle);
        window.dispatchEvent(new CustomEvent("symphonia:specWorkspaceChanged", { detail: { repoKey } }));
        router.push(
          `/r/${repoKey.toLowerCase()}/workspace/${encodeURIComponent(
            artifact.type,
          )}/${encodeURIComponent(artifact.id)}`,
        );
        setOpen(false);
      } catch (err) {
        setMessages((m) => [
          ...m,
          {
            id: `e${Date.now()}`,
            role: "clarise",
            content: err instanceof Error ? err.message : "Could not create document.",
          },
        ]);
      }
      return;
    }

    if (!("category" in msg.saveable)) return;
    const category = overrideCategory ?? msg.saveable.category;
    if (category === "task") {
      newTask.open({
        title: msg.saveable.suggestedTitle,
        body: msg.content,
      });
      setOpen(false);
      return;
    }
    startDraft(repoKey, category, {
      title: msg.saveable.suggestedTitle,
      body: msg.content,
    });
    setOpen(false);
  };

  if (!open && isRepoHome) {
    return null;
  }

  if (!open) {
    return (
      <button
        onClick={() => router.push(`/r/${repoKey.toLowerCase()}`)}
        aria-label="Open Clarise"
        className="fixed bottom-4 right-4 z-30 inline-flex items-center gap-2 rounded-full border bg-card px-3.5 py-2 text-xs font-medium shadow-lg hover:bg-accent transition-colors"
      >
        <Sparkles className="h-3.5 w-3.5 text-violet-500" />
        Ask Clarise
      </button>
    );
  }

  return (
    <div
      role="dialog"
      aria-label="Clarise"
      className="fixed bottom-4 right-4 z-30 flex w-[calc(100%-2rem)] sm:w-[26rem] max-h-[70svh] flex-col rounded-xl border bg-card shadow-2xl"
    >
      <header className="flex items-center justify-between border-b px-3 py-2">
        <div className="flex items-center gap-2 text-sm">
          <span className="grid h-6 w-6 place-items-center rounded-md bg-violet-500/15 text-violet-500">
            <Sparkles className="h-3.5 w-3.5" />
          </span>
          <span className="font-medium">Clarise</span>
          <span className="text-[11px] text-muted-foreground font-mono">{repoKey}</span>
        </div>
        <button
          onClick={() => setOpen(false)}
          aria-label="Close Clarise"
          className="grid h-6 w-6 place-items-center rounded hover:bg-accent text-muted-foreground"
        >
          <X className="h-3.5 w-3.5" />
        </button>
      </header>

      <div ref={listRef} className="flex-1 overflow-y-auto px-3 py-3 space-y-2">
        {messages.map((m) => (
          <div key={m.id} className={cn("space-y-1", m.role === "user" && "text-right")}>
            <div
              className={cn(
                "inline-block max-w-[90%] whitespace-pre-wrap rounded-lg px-3 py-2 text-sm leading-relaxed text-left",
                m.role === "user"
                  ? "bg-primary text-primary-foreground"
                  : "bg-muted text-foreground",
              )}
            >
              {m.content}
            </div>
            {m.role === "clarise" && m.saveable && (
              <div className="flex flex-wrap items-center gap-1.5 pl-1">
                {"category" in m.saveable ? (
                  <>
                    <span className="text-[11px] text-muted-foreground">Save as:</span>
                    <DraftPill onClick={() => void handleSaveAsDraft(m)}>
                      {CATEGORY_SINGULAR[m.saveable.category]}
                    </DraftPill>
                    {m.saveable.category !== "doc" && (
                      <DraftPill onClick={() => void handleSaveAsDraft(m, "doc")}>Doc</DraftPill>
                    )}
                    {m.saveable.category !== "decision" && (
                      <DraftPill onClick={() => void handleSaveAsDraft(m, "decision")}>
                        Decision
                      </DraftPill>
                    )}
                  </>
                ) : (
                  <>
                    <span className="text-[11px] text-muted-foreground">Planning:</span>
                    <DraftPill onClick={() => void handleSaveAsDraft(m)}>
                      {specActionLabel(m.saveable.specAction)}
                    </DraftPill>
                  </>
                )}
                <span className="text-[10px] text-muted-foreground/70">
                  Opens an editable file
                </span>
              </div>
            )}
          </div>
        ))}
      </div>

      {messages.length <= 1 && (
        <div className="flex flex-wrap gap-1.5 px-3 pb-2">
          {SUGGESTIONS.map((s) => (
            <button
              key={s}
              onClick={() => send(s)}
              className="rounded-full border px-2.5 py-1 text-[11px] text-muted-foreground hover:bg-accent hover:text-foreground"
            >
              {s}
            </button>
          ))}
        </div>
      )}

      <form
        onSubmit={(e) => {
          e.preventDefault();
          send(draft);
        }}
        className="flex items-end gap-2 border-t px-3 py-2"
      >
        <textarea
          ref={inputRef}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              send(draft);
            }
          }}
          rows={1}
          placeholder="Ask Clarise — Enter to send, Shift+Enter for newline"
          aria-label="Message Clarise"
          className="flex-1 resize-none bg-transparent text-sm placeholder:text-muted-foreground/70 outline-none max-h-32"
        />
        <button
          type="submit"
          disabled={!draft.trim()}
          aria-label="Send"
          className="grid h-7 w-7 place-items-center rounded-md bg-primary text-primary-foreground disabled:opacity-40 disabled:cursor-not-allowed"
        >
          <Send className="h-3.5 w-3.5" />
        </button>
      </form>
    </div>
  );
}

function DraftPill({
  children,
  onClick,
}: {
  children: ReactNode;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] hover:bg-accent"
    >
      <FilePlus2 className="h-3 w-3" />
      {children}
    </button>
  );
}

async function createSpecArtifact(
  repoKey: string,
  action: "starter_codebase_map" | "starter_milestone" | "decision_record",
  title: string,
): Promise<{ type: string; id: string }> {
  if (action === "starter_codebase_map") {
    const res = await fetch(
      `/api/repositories/${encodeURIComponent(repoKey)}/spec-workspace/initialize`,
      { method: "POST" },
    );
    const payload = (await res.json()) as { error?: string };
    if (!res.ok) throw new Error(payload.error ?? "Could not create codebase map.");
    return { type: "codebase_map", id: "codebase-map" };
  }

  const endpoint = action === "starter_milestone" ? "milestones" : "decisions";
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/spec-workspace/${endpoint}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ title }),
    },
  );
  const payload = (await res.json()) as {
    artifact?: { type: string; id: string };
    error?: string;
  };
  if (!res.ok || !payload.artifact) {
    throw new Error(payload.error ?? "Could not create document.");
  }
  return payload.artifact;
}

function specActionLabel(
  action: "starter_codebase_map" | "starter_milestone" | "decision_record",
) {
  switch (action) {
    case "starter_codebase_map":
      return "Open codebase map";
    case "starter_milestone":
      return "Create milestone";
    case "decision_record":
      return "Create decision";
  }
}

/**
 * Mock Clarise responder. The point is to show deterministic starter actions;
 * chat is never silently persisted.
 */
function respond(prompt: string, repo: string): Pick<Message, "content" | "saveable"> {
  const p = prompt.toLowerCase();

  if (p.includes("workflow") || p.includes("workflow.md")) {
    return {
      content:
        "# Repository rules\n# Review-first — humans review the run summary in Symphonía before any PR.\n\n" +
        "on_task_started:\n  - assign: claude\n  - require_review: true\n\n" +
        "on_run_complete:\n  - status: in_review\n  - request_review_from: assignees\n\n" +
        "on_review_approved:\n  - open_pr: true\n\n" +
        "on_pr_merged:\n  - status: completed\n",
      saveable: { category: "workflow", suggestedTitle: "Repository rules" },
    };
  }

  if (p.includes("codebase map") || p.includes("map the codebase")) {
    return {
      content:
        "# Codebase Map\n\n## Purpose\n\n## Entry points\n\n## Important paths\n\n## Data and state\n\n## Open questions\n",
      saveable: {
        specAction: "starter_codebase_map",
        suggestedTitle: "Codebase map",
      },
    };
  }

  if (p.includes("milestone")) {
    return {
      content:
        "# Milestone 001 — Untitled\n\n## Goal\n\n## Why this matters\n\n## Scope\n\n## Non-goals\n\n## Acceptance criteria\n\n## Open questions\n\n## Related artifacts\n",
      saveable: {
        specAction: "starter_milestone",
        suggestedTitle: "Untitled milestone",
      },
    };
  }

  if (p.includes("requirements")) {
    return {
      content:
        "# Requirements 001 — Untitled requirements\n\n## User needs\n\n## Functional requirements\n\n## Constraints\n\n## Acceptance criteria\n",
    };
  }

  if (p.includes("plan")) {
    return {
      content:
        "# Plan 001 — Untitled plan\n\n## Objective\n\n## Steps\n\n## Validation\n\n## Risks\n\n## Related milestone\n",
    };
  }

  if (p.includes("acceptance") || p.includes("brief") || p.includes("task")) {
    return {
      content:
        "# Improve repository overview\n\n" +
        "## Goal\n\nMake the Tasks board easier to scan at a glance and remember the user's view choice.\n\n" +
        "## Context\n\nUsers are asking for a stable default and a clearer status grouping.\n\n" +
        "## Acceptance criteria\n\n- [ ] Board is the default view\n- [ ] List remains available\n" +
        "- [ ] The chosen view is remembered per repository\n- [ ] Empty status columns still render\n\n" +
        "## Linked sources\n\n- " +
        repo +
        " repository overview\n\n## Notes\n\nKeep card density tight — long titles should clamp.",
      saveable: { category: "task", suggestedTitle: "Improve repository overview" },
    };
  }

  if (p.includes("decision")) {
    return {
      content:
        "# Repository documents are the source of truth\n\n**Status:** Proposed\n\n" +
        "## Context\n\nWe want durable, reviewable planning records.\n\n" +
        "## Decision\n\nTasks, Projects, Docs, Decisions, Reviews and Run Summaries are stored in the repository. " +
        "GitHub/Linear issues are linked projections only.\n\n" +
        "## Why\n\nRepository-backed records review cleanly in pull requests and survive tool changes.\n\n" +
        "## Consequences\n\n- Planning memory lives next to code.\n- We cannot rely on database-only state.\n",
      saveable: {
        specAction: "decision_record",
        suggestedTitle: "Repository documents are the source of truth",
      },
    };
  }

  if (p.includes("summary") || p.includes("summarize") || p.includes("run")) {
    return {
      content:
        "# Clarise run - overview card density\n\n**Assistant:** Clarise\n\n" +
        "**Files changed:** 4\n\n**Summary.** Tightened card padding, switched to tabular numerals " +
        "for IDs, and added a 2-line clamp on titles.\n\n**Validation.** Tests passed. Lint clean.\n",
      saveable: {
        category: "run-summary",
        suggestedTitle: "Clarise run - overview card density",
      },
    };
  }

  if (p.includes("review")) {
    return {
      content:
        "# Tasks redesign - review notes\n\n## Went well\n\n- Board default feels right.\n\n" +
        "## Needs work\n\n- Long titles still wrap awkwardly on narrow viewports.\n\n" +
        "## Follow-ups\n\n- Add filters by assignee.",
      saveable: {
        category: "review",
        suggestedTitle: "Tasks redesign - review notes",
      },
    };
  }

  return {
    content:
      "Got it. I'll keep this scoped to " +
      repo +
      " so I don't pull in unrelated context. Ask me for a starter codebase map, milestone, decision, requirements, plan, or task.",
  };
}
