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
import { Sparkles, Send, X, FilePlus2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { CATEGORY_SINGULAR, type DocCategory } from "@/lib/docs-store";
import { useDraftHost } from "@/components/draft-host";

interface Message {
  id: string;
  role: "user" | "clarise";
  content: string;
  /** If set, this message can be saved as a new draft of the given category. */
  saveable?: { category: DocCategory; suggestedTitle: string };
}

const SUGGESTIONS = [
  "Draft a task brief for the next priority",
  "Draft acceptance criteria from these notes",
  "Summarize the latest run on this task",
  "Draft a decision: Markdown is the source of truth",
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
      content: `Hi — I'm Clarise. I can help draft Tasks, Docs, Decisions, Reviews, Run Summaries, or WORKFLOW.md for ${repoKey}. Anything I draft goes into the workspace editor as an editable draft so you can review before saving.`,
    },
  ]);
  const [draft, setDraft] = useState("");
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const { startDraft } = useDraftHost();
  const { openSignal } = useContext(SignalCtx);

  // Open when the command palette pings.
  useEffect(() => {
    if (openSignal > 0) setOpen(true);
  }, [openSignal]);

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

  const handleSaveAsDraft = (
    msg: Message,
    overrideCategory?: DocCategory,
  ) => {
    if (!msg.saveable) return;
    const category = overrideCategory ?? msg.saveable.category;
    startDraft(repoKey, category, {
      title: msg.saveable.suggestedTitle,
      body: msg.content,
    });
    setOpen(false);
  };

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
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
                <span className="text-[11px] text-muted-foreground">Save as:</span>
                <DraftPill onClick={() => handleSaveAsDraft(m)}>
                  {CATEGORY_SINGULAR[m.saveable.category]}
                </DraftPill>
                {m.saveable.category !== "doc" && (
                  <DraftPill onClick={() => handleSaveAsDraft(m, "doc")}>Doc</DraftPill>
                )}
                {m.saveable.category !== "decision" && (
                  <DraftPill onClick={() => handleSaveAsDraft(m, "decision")}>
                    Decision
                  </DraftPill>
                )}
                <span className="text-[10px] text-muted-foreground/70">
                  Opens an editable draft
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

/**
 * Mock Clarise responder. The point is to show the save-as-draft handoff;
 * everything is local. Chat is never silently persisted.
 */
function respond(prompt: string, repo: string): Pick<Message, "content" | "saveable"> {
  const p = prompt.toLowerCase();

  if (p.includes("workflow") || p.includes("workflow.md")) {
    return {
      content:
        "# WORKFLOW.md\n# Review-first — humans review the run summary in Symphonía before any PR.\n\n" +
        "on_task_started:\n  - assign: claude\n  - require_review: true\n\n" +
        "on_run_complete:\n  - status: in_review\n  - request_review_from: assignees\n\n" +
        "on_review_approved:\n  - open_pr: true\n\n" +
        "on_pr_merged:\n  - status: completed\n",
      saveable: { category: "workflow", suggestedTitle: "WORKFLOW.md" },
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
        "# Markdown is the source of truth\n\n**Status:** Proposed\n\n" +
        "## Context\n\nWe want durable, reviewable, portable workspace memory.\n\n" +
        "## Decision\n\nTasks, Projects, Docs, Decisions, Reviews and Run Summaries are stored as Markdown in the repository. " +
        "GitHub/Linear issues are linked projections only.\n\n" +
        "## Why\n\nMarkdown diffs cleanly in PRs and survives tool changes.\n\n" +
        "## Consequences\n\n- Workspace memory lives next to code.\n- We cannot rely on database-only state.\n",
      saveable: {
        category: "decision",
        suggestedTitle: "Markdown is the source of truth",
      },
    };
  }

  if (p.includes("summary") || p.includes("summarize") || p.includes("run")) {
    return {
      content:
        "# Codex run — overview card density\n\n**Coding Assistant:** Codex\n\n" +
        "**Files changed:** 4\n\n**Summary.** Tightened card padding, switched to tabular numerals " +
        "for IDs, and added a 2-line clamp on titles.\n\n**Validation.** Tests passed. Lint clean.\n",
      saveable: {
        category: "run-summary",
        suggestedTitle: "Codex run — overview card density",
      },
    };
  }

  if (p.includes("review")) {
    return {
      content:
        "# Overview redesign — review notes\n\n## Went well\n\n- Board default feels right.\n\n" +
        "## Needs work\n\n- Long titles still wrap awkwardly on narrow viewports.\n\n" +
        "## Follow-ups\n\n- Add filters by assignee.",
      saveable: {
        category: "review",
        suggestedTitle: "Overview redesign — review notes",
      },
    };
  }

  return {
    content:
      "Got it. I'll keep this scoped to " +
      repo +
      " so I don't pull in unrelated context. If you want a durable page, I can hand off any answer to the workspace editor — just ask me to draft a Task, Doc, Decision, Review, Run Summary, or WORKFLOW.md.",
  };
}
