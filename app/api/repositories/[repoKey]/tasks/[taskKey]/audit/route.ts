import { proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ repoKey: string; taskKey: string }> },
) {
  const { repoKey, taskKey } = await params;
  const url = new URL(request.url);
  return proxyToSymphoniaService(
    `/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(
      taskKey,
    )}/audit${url.search}`,
    {},
    request,
  );
}
