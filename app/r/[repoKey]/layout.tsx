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
  const key = repoKey.toUpperCase();

  return (
    <DocsProvider>
      <NewTaskProvider repoKey={key}>
        <RepoLayoutClient repoKey={key}>
          {children}
          <Clarise repoKey={key} />
        </RepoLayoutClient>
      </NewTaskProvider>
    </DocsProvider>
  );
}
