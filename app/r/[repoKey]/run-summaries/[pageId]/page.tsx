import { PageEditor } from "@/components/page-editor";

export default async function RunSummaryPage({
  params,
}: {
  params: Promise<{ repoKey: string; pageId: string }>;
}) {
  const { repoKey, pageId } = await params;
  return (
    <PageEditor
      repoKey={repoKey.toUpperCase()}
      pageId={pageId}
      category="run-summary"
    />
  );
}
