import { proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ repoKey: string }> },
) {
  const { repoKey } = await params;
  const url = new URL(request.url);
  return proxyToSymphoniaService(
    `/api/repositories/${encodeURIComponent(repoKey)}/audit${url.search}`,
    {},
    request,
  );
}
