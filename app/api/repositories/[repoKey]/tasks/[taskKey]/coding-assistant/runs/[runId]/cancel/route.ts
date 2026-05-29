import { proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ repoKey: string; taskKey: string; runId: string }> },
) {
  const { repoKey, taskKey, runId } = await params;
  return proxyToSymphoniaService(
    `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(
      taskKey,
    )}/coding-assistant/runs/${encodeURIComponent(runId)}/cancel`,
    { method: "POST" },
    request,
  );
}
