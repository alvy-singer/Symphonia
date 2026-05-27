import { ClariseRepoHome } from "@/components/clarise-repo-home";

export default async function RepoIndex({
  params,
}: {
  params: Promise<{ repoKey: string }>;
}) {
  const { repoKey } = await params;
  return <ClariseRepoHome repoKey={repoKey.toUpperCase()} />;
}
