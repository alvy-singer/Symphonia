import { redirect } from "next/navigation";

export default async function RepoIndex({
  params,
}: {
  params: Promise<{ repoKey: string }>;
}) {
  const { repoKey } = await params;
  redirect(`/r/${repoKey}/tasks`);
}
