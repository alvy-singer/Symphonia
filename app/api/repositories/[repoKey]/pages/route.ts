import { jsonBody, proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ repoKey: string }> },
) {
  const { repoKey } = await params;
  const url = new URL(request.url);
  return proxyToSymphoniaService(
    `/api/repositories/${encodeURIComponent(repoKey)}/pages${url.search}`,
  );
}

export async function POST(
  request: Request,
  { params }: { params: Promise<{ repoKey: string }> },
) {
  const { repoKey } = await params;
  return proxyToSymphoniaService(`/api/repositories/${encodeURIComponent(repoKey)}/pages`, {
    method: "POST",
    body: await jsonBody(request),
  }, request);
}
