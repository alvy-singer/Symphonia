"use client";

import { notFound } from "next/navigation";
import { useDocs, type DocCategory } from "@/lib/docs-store";
import { MarkdownEditor } from "@/components/editor/markdown-editor";

interface Props {
  repoKey: string;
  pageId: string;
  /** Limit the editor to a category (used as a sanity check on the URL). */
  category?: DocCategory;
}

/**
 * Renders a single saved page in the workspace editor. The page is looked up
 * from the docs store by id. If the id does not belong to this repo or
 * category, we return notFound so the user lands on the section list.
 */
export function PageEditor({ repoKey, pageId, category }: Props) {
  const { byId } = useDocs();
  const page = byId(pageId);
  if (!page || page.repo !== repoKey || (category && page.category !== category)) {
    notFound();
  }
  return <MarkdownEditor page={page!} />;
}
