import { TaskPage } from "@/components/task-page";

export default async function TaskDetail({
  params,
}: {
  params: Promise<{ repoKey: string; taskKey: string }>;
}) {
  const { repoKey, taskKey } = await params;
  return (
    <TaskPage
      repoKey={repoKey.toUpperCase()}
      pageIdOrTaskKey={decodeURIComponent(taskKey)}
    />
  );
}
