import { redirect } from "next/navigation";

export default async function DocsIndex({
  params,
}: {
  params: Promise<{ repoKey: string }>;
}) {
  const { repoKey } = await params;
  redirect(`/r/${repoKey.toLowerCase()}`);
}
