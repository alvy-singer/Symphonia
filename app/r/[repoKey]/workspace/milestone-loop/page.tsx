import { ClariseMilestoneLoop } from "@/components/clarise-milestone-loop";

export default async function WorkspaceMilestoneLoopPage({
  params,
}: {
  params: Promise<{ repoKey: string }>;
}) {
  const { repoKey } = await params;
  return <ClariseMilestoneLoop repoKey={repoKey.toUpperCase()} />;
}
