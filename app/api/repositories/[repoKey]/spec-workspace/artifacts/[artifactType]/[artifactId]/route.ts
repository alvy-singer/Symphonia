import { jsonBody, proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ repoKey: string; artifactType: string; artifactId: string }> },
) {
  const { repoKey, artifactType, artifactId } = await params;
  return proxyToSymphoniaService(
    `/api/repositories/${encodeURIComponent(repoKey)}/spec-workspace/artifacts/${encodeURIComponent(
      artifactType,
    )}/${encodeURIComponent(artifactId)}`,
  );
}

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ repoKey: string; artifactType: string; artifactId: string }> },
) {
  const { repoKey, artifactType, artifactId } = await params;
  return proxyToSymphoniaService(
    `/api/repositories/${encodeURIComponent(repoKey)}/spec-workspace/artifacts/${encodeURIComponent(
      artifactType,
    )}/${encodeURIComponent(artifactId)}`,
    {
      method: "PATCH",
      body: await jsonBody(request),
    },
    request,
  );
}
