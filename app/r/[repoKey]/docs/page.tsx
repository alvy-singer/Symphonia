import { DocListView } from "@/components/doc-list-view";

export default async function DocsIndex({
  params,
}: {
  params: Promise<{ repoKey: string }>;
}) {
  const { repoKey } = await params;
  return (
    <DocListView
      repoKey={repoKey.toUpperCase()}
      category="doc"
      basePath="docs"
      description="Long-form documents that live in the repository as Markdown. Architecture notes, runbooks, onboarding — anything you want a teammate (or a Coding Assistant) to find in three months."
      emptyHint="Pages save under symphonia/docs/. Nest pages by opening a child draft from a parent page."
    />
  );
}
