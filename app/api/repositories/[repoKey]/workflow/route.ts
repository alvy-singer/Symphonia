import { jsonBody, proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ repoKey: string }> },
) {
  const { repoKey } = await params;
  return proxyToSymphoniaService(`/api/repositories/${encodeURIComponent(repoKey)}/workflow`);
}

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ repoKey: string }> },
) {
  const { repoKey } = await params;
  return proxyToSymphoniaService(`/api/repositories/${encodeURIComponent(repoKey)}/workflow`, {
    method: "PATCH",
    body: await jsonBody(request),
  }, request);
}
