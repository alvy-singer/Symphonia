import { DocListView } from "@/components/doc-list-view";

export default async function ReviewsIndex({
  params,
}: {
  params: Promise<{ repoKey: string }>;
}) {
  const { repoKey } = await params;
  return (
    <DocListView
      repoKey={repoKey.toUpperCase()}
      category="review"
      basePath="reviews"
      description="Review notes from humans (or from review-first workflows). Pair these with the linked Run Summaries to keep the context next to the work."
    />
  );
}
