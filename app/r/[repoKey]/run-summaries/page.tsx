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
      description="Human-readable summaries of Coding Assistant runs — what changed, what was validated, where the assistant made conservative choices. Raw run logs are not committed."
    />
  );
}
