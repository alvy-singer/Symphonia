import { MembersView } from "@/components/members-view";

export default async function MembersPage({
  params,
}: {
  params: Promise<{ repoKey: string }>;
}) {
  const { repoKey } = await params;
  return <MembersView repoKey={repoKey.toUpperCase()} />;
}
