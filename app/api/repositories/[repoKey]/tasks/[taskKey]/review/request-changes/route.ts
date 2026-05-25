import { jsonBody, proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ repoKey: string; taskKey: string }> },
) {
  const { repoKey, taskKey } = await params;
  return proxyToSymphoniaService(
    `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(
      taskKey,
    )}/review/request-changes`,
    {
      method: "POST",
      body: await jsonBody(request),
    },
  );
}
