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
      description="Long-form documents for architecture notes, runbooks, onboarding, and anything you want a teammate or Clarise to find in three months."
      emptyHint="Pages save under symphonia/docs/. Nest pages by opening a child draft from a parent page."
    />
  );
}
