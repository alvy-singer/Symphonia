import { PageEditor } from "@/components/page-editor";

export default async function DocPage({
  params,
}: {
  params: Promise<{ repoKey: string; pageId: string }>;
}) {
  const { repoKey, pageId } = await params;
  return <PageEditor repoKey={repoKey.toUpperCase()} pageId={pageId} category="doc" />;
}
