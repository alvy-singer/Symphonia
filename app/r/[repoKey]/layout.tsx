import { notFound } from "next/navigation";
import { repositories } from "@/data/mock";
import { DocsProvider } from "@/lib/docs-store";
import { NewTaskProvider } from "@/components/new-task-dialog";
import { Clarise } from "@/components/clarise";
import { RepoLayoutClient } from "@/components/repo-layout-client";

export default async function RepoLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ repoKey: string }>;
}) {
  const { repoKey } = await params;
  const repo = repositories.find((r) => r.key.toLowerCase() === repoKey.toLowerCase());
  if (!repo) notFound();

  return (
    <DocsProvider>
      <NewTaskProvider>
        <RepoLayoutClient repoKey={repo.key}>
          {children}
          <Clarise repoKey={repo.key} />
        </RepoLayoutClient>
      </NewTaskProvider>
    </DocsProvider>
  );
}
