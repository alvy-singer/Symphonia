import { notFound } from "next/navigation";

export default async function WorkspacePage({
  params: _params,
}: {
  params: Promise<{ repoKey: string }>;
}) {
  notFound();
}
