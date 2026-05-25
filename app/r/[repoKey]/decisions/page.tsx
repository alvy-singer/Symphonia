import { DocListView } from "@/components/doc-list-view";

export default async function DecisionsIndex({
  params,
}: {
  params: Promise<{ repoKey: string }>;
}) {
  const { repoKey } = await params;
  return (
    <DocListView
      repoKey={repoKey.toUpperCase()}
      category="decision"
      basePath="decisions"
      description="Architecture and product decisions, captured close to the code. Each decision has a status (Proposed, Accepted, Superseded), the why, and the consequences."
      emptyHint="A good first decision: repository documents are the source of truth."
    />
  );
}
