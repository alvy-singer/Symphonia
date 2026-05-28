import { GroupChatView } from "@/components/group-chat-view";

export default async function GroupChatPage({
  params,
}: {
  params: Promise<{ repoKey: string }>;
}) {
  const { repoKey } = await params;
  return <GroupChatView repoKey={repoKey.toUpperCase()} />;
}
