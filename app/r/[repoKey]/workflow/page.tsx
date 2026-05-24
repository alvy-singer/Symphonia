import { WorkflowView } from "@/components/workflow-view";

export default async function WorkflowPage({
  params,
}: {
  params: Promise<{ repoKey: string }>;
}) {
  const { repoKey } = await params;
  return <WorkflowView repoKey={repoKey.toUpperCase()} />;
}
