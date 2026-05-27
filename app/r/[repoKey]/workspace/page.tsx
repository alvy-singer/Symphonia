import { SpecWorkspaceIndex } from "@/components/spec-workspace-index";

export default async function WorkspacePage({
  params,
}: {
  params: Promise<{ repoKey: string }>;
}) {
  const { repoKey } = await params;
  return <SpecWorkspaceIndex repoKey={repoKey.toUpperCase()} />;
}
