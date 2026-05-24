import { ProjectsView } from "@/components/projects-view";

export default async function ProjectsPage({
  params,
}: {
  params: Promise<{ repoKey: string }>;
}) {
  const { repoKey } = await params;
  return <ProjectsView repoKey={repoKey.toUpperCase()} />;
}
