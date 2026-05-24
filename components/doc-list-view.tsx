"use client";

import Link from "next/link";
import { useMemo } from "react";
import { Plus } from "lucide-react";
import {
  CATEGORY_LABELS,
  useDocs,
  type DocCategory,
  type DocPage,
} from "@/lib/docs-store";
import { useDraftHost } from "@/components/draft-host";

interface Props {
  repoKey: string;
  category: DocCategory;
  /** Section path segment, e.g. "docs", "decisions". */
  basePath: string;
  description: string;
  /** Optional empty-state suggestion to nudge the right next step. */
  emptyHint?: string;
}

/**
 * Generic list view used by Docs, Decisions, Reviews, and Run Summaries.
 *
 * Answers the "what / why / what next" expected of every screen:
 *   - heading + count = what am I looking at
 *   - description     = why does it matter
 *   - "New <singular>" = what can I do next
 */
export function DocListView({
  repoKey,
  category,
  basePath,
  description,
  emptyHint,
}: Props) {
  const { forRepo } = useDocs();
  const { startDraft } = useDraftHost();
  const repoSlug = repoKey.toLowerCase();
  const pages = useMemo(
    () => forRepo(repoKey).filter((p) => p.category === category),
    [forRepo, repoKey, category],
  );
  const heading = CATEGORY_LABELS[category];
  const singular = heading.replace(/s$/, "");

  return (
    <div className="flex h-full flex-col">
      <header className="flex flex-wrap items-center justify-between gap-3 border-b px-4 py-2.5">
        <div className="flex items-center gap-2 text-sm">
          <span className="font-semibold">{heading}</span>
          <span className="text-muted-foreground tabular-nums">{pages.length}</span>
        </div>
        <button
          onClick={() => startDraft(repoKey, category)}
          className="inline-flex items-center gap-1.5 rounded-md bg-primary text-primary-foreground px-2.5 py-1 text-[12px] hover:opacity-90"
        >
          <Plus className="h-3.5 w-3.5" /> New {singular}
        </button>
      </header>

      <div className="flex-1 overflow-y-auto">
        <div className="mx-auto w-full max-w-3xl px-4 py-5">
          <p className="mb-5 text-sm text-muted-foreground">{description}</p>

          {pages.length === 0 ? (
            <div className="rounded-lg border border-dashed p-8 text-center">
              <p className="text-sm font-medium">No {heading.toLowerCase()} yet</p>
              <p className="mx-auto mt-1 max-w-md text-xs text-muted-foreground">
                {emptyHint ??
                  `Pages live as Markdown under symphonia/${basePath}/. Open one as an editable draft to get started.`}
              </p>
              <button
                onClick={() => startDraft(repoKey, category)}
                className="mt-4 inline-flex items-center gap-1.5 rounded-md bg-primary text-primary-foreground px-2.5 py-1 text-[12px] hover:opacity-90"
              >
                <Plus className="h-3.5 w-3.5" /> New {singular}
              </button>
            </div>
          ) : (
            <ul className="grid gap-2">
              {pages.map((p) => (
                <PageRow key={p.id} page={p} repoSlug={repoSlug} basePath={basePath} />
              ))}
            </ul>
          )}
        </div>
      </div>
    </div>
  );
}

function PageRow({
  page,
  repoSlug,
  basePath,
}: {
  page: DocPage;
  repoSlug: string;
  basePath: string;
}) {
  const preview = page.body
    .replace(/^#+\s+.*\n+/, "")
    .replace(/\s+/g, " ")
    .slice(0, 160);
  return (
    <li>
      <Link
        href={`/r/${repoSlug}/${basePath}/${page.id}`}
        className="block rounded-lg border bg-card px-3 py-2.5 hover:border-foreground/20 transition-colors"
      >
        <div className="flex items-start gap-3">
          <span aria-hidden className="text-lg leading-none">
            {page.icon ?? "·"}
          </span>
          <div className="min-w-0 flex-1">
            <h3 className="text-sm font-medium truncate">
              {page.title || (
                <span className="italic text-muted-foreground">Untitled</span>
              )}
            </h3>
            {preview && (
              <p className="mt-0.5 text-xs text-muted-foreground line-clamp-1">
                {preview}
              </p>
            )}
            <p className="mt-1 text-[11px] text-muted-foreground font-mono">
              {page.path}
            </p>
          </div>
        </div>
      </Link>
    </li>
  );
}
