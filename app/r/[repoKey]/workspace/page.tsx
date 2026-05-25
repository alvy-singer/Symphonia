import { ClariseMilestoneLoop } from "@/components/clarise-milestone-loop";

export default async function WorkspacePage({
  params,
}: {
  params: Promise<{ repoKey: string }>;
}) {
  const { repoKey } = await params;
  return <ClariseMilestoneLoop repoKey={repoKey.toUpperCase()} />;
}
