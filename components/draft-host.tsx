"use client";

import {
  createContext,
  useCallback,
  useContext,
  useState,
  type ReactNode,
} from "react";
import { useRouter } from "next/navigation";
import { MarkdownEditor } from "@/components/editor/markdown-editor";
import { useDocs, type DocCategory, type DocPage } from "@/lib/docs-store";

interface DraftHostCtx {
  /**
   * Start a new draft of the given category and open it as a full-screen
   * editable draft in the workspace. Returns the draft page so the caller can
   * pre-fill content (used by Clarise to hand a drafted body to the editor).
   */
  startDraft: (
    repo: string,
    category: DocCategory,
    init?: Partial<Pick<DocPage, "title" | "body" | "icon" | "parentId" | "links" | "meta">>,
  ) => DocPage;
}

const Ctx = createContext<DraftHostCtx>({
  startDraft: () => {
    throw new Error("DraftHost not mounted");
  },
});
export const useDraftHost = () => useContext(Ctx);

const CATEGORY_PLACEHOLDERS: Record<DocCategory, string> = {
  task:
    "Goal\n\nContext\n\nAcceptance criteria\n- [ ] \n\nNotes\n\nLinked sources\n\nReview notes\n\nRun summaries",
  project:
    "Goal\n\nMilestones\n\nMembers\n\nLinks\n\nRisks",
  doc: "Outline what you want to document. Formatting is preserved.",
  decision:
    "Status: Proposed\n\nContext\n\nDecision\n\nWhy\n\nConsequences",
  review:
    "What was reviewed\n\nWent well\n\nNeeds work\n\nFollow-ups",
  "run-summary": "Clarise: \n\nFiles changed\n\nSummary\n\nValidation",
  workflow: "",
};

const CATEGORY_TITLE_HINT: Record<DocCategory, string> = {
  task: "New Task",
  project: "New Project",
  doc: "New Doc",
  decision: "New Decision",
  review: "New Review",
  "run-summary": "New Run Summary",
  workflow: "Automation Rules",
};

/**
 * Hosts an inline draft above the regular workspace content. When a draft is
 * open, the workspace content is dimmed/hidden behind the editor. Saving the
 * draft writes it to the repository (the docs store) and routes the user to
 * the saved page so the URL is shareable.
 */
export function DraftHost({ children }: { children: ReactNode }) {
  const { newDraft, saveDraft, discardDraft } = useDocs();
  const [draft, setDraft] = useState<DocPage | null>(null);
  const router = useRouter();

  const startDraft = useCallback<DraftHostCtx["startDraft"]>(
    (repo, category, init) => {
      const created = newDraft(repo, category, {
        title: init?.title ?? "",
        body: init?.body ?? CATEGORY_PLACEHOLDERS[category],
        icon: init?.icon,
        parentId: init?.parentId,
        links: init?.links,
        meta: init?.meta,
      });
      setDraft(created);
      return created;
    },
    [newDraft],
  );

  const close = () => setDraft(null);

  const onSave = () => {
    if (!draft) return;
    const saved = saveDraft(draft.id);
    setDraft(null);
    if (saved) {
      const slug = saved.repo.toLowerCase();
      const sectionByCategory: Record<DocCategory, string> = {
        task: "tasks",
        project: "projects",
        doc: "docs",
        decision: "decisions",
        review: "reviews",
        "run-summary": "run-summaries",
        workflow: "workflow",
      };
      const section = sectionByCategory[saved.category];
      const href =
        saved.category === "workflow"
          ? `/r/${slug}/workflow`
          : `/r/${slug}/${section}/${saved.id}`;
      router.push(href);
    }
  };

  const onDiscard = () => {
    if (!draft) return;
    discardDraft(draft.id);
    setDraft(null);
  };

  return (
    <Ctx.Provider value={{ startDraft }}>
      {children}
      {draft && (
        <div
          role="dialog"
          aria-label={CATEGORY_TITLE_HINT[draft.category]}
          aria-modal="true"
          className="fixed inset-0 z-40 flex flex-col bg-background"
        >
          <div className="flex items-center justify-between border-b px-4 py-2">
            <div className="flex items-center gap-2 text-xs text-muted-foreground">
              <span className="rounded-full bg-amber-500/15 px-2 py-0.5 text-[10px] font-medium text-amber-600 dark:text-amber-400">
                Draft
              </span>
              <span className="font-mono">{draft.repo}</span>
              <span>·</span>
              <span>{CATEGORY_TITLE_HINT[draft.category]}</span>
            </div>
            <button
              onClick={onDiscard}
              className="text-xs text-muted-foreground hover:text-foreground"
            >
              Close without saving
            </button>
          </div>
          <div className="flex-1 min-h-0">
            <MarkdownEditor
              page={draft}
              isDraft
              onSave={onSave}
              onDiscard={onDiscard}
              bodyPlaceholder={CATEGORY_PLACEHOLDERS[draft.category]}
            />
          </div>
        </div>
      )}
    </Ctx.Provider>
  );
}
