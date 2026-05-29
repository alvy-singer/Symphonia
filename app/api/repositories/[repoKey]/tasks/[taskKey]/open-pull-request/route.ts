import { proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ repoKey: string; taskKey: string }> },
) {
  const { repoKey, taskKey } = await params;
  return proxyToSymphoniaService(
    `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(taskKey)}/open-pull-request`,
    {
      method: "POST",
      body: "{}",
    },
    request,
  );
}
