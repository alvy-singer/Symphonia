import { TasksView } from "@/components/tasks-view";

export default async function TasksPage({
  params,
}: {
  params: Promise<{ repoKey: string }>;
}) {
  const { repoKey } = await params;
  return <TasksView repoKey={repoKey.toUpperCase()} />;
}
