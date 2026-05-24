import { InboxView } from "@/components/inbox-view";

export default async function InboxPage({
  params,
}: {
  params: Promise<{ repoKey: string }>;
}) {
  const { repoKey } = await params;
  return <InboxView repoKey={repoKey.toUpperCase()} />;
}
