import { jsonBody, proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ repoKey: string; artifactType: string; artifactId: string }> },
) {
  const { repoKey, artifactType, artifactId } = await params;
  return proxyToSymphoniaService(
    `/api/repositories/${encodeURIComponent(repoKey)}/private-workspace/artifacts/${encodeURIComponent(
      artifactType,
    )}/${encodeURIComponent(artifactId)}/export/github/open-pr`,
    {
      method: "POST",
      body: await jsonBody(request),
    },
    request,
  );
}
