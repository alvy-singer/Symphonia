import { DocListView } from "@/components/doc-list-view";

export default async function RunSummariesIndex({
  params,
}: {
  params: Promise<{ repoKey: string }>;
}) {
  const { repoKey } = await params;
  return (
    <DocListView
      repoKey={repoKey.toUpperCase()}
      category="run-summary"
      basePath="run-summaries"
      description="Human-readable summaries of Clarise runs: what changed, what was validated, and where Clarise made conservative choices."
    />
  );
}
