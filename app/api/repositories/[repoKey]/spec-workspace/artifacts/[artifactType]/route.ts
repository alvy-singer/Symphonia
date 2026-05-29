import { jsonBody, proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ repoKey: string; artifactType: string }> },
) {
  const { repoKey, artifactType } = await params;
  return proxyToSymphoniaService(
    `/api/repositories/${encodeURIComponent(repoKey)}/spec-workspace/artifacts/${encodeURIComponent(
      artifactType,
    )}`,
  );
}

export async function POST(
  request: Request,
  { params }: { params: Promise<{ repoKey: string; artifactType: string }> },
) {
  const { repoKey, artifactType } = await params;
  return proxyToSymphoniaService(
    `/api/repositories/${encodeURIComponent(repoKey)}/spec-workspace/artifacts/${encodeURIComponent(
      artifactType,
    )}`,
    {
      method: "POST",
      body: await jsonBody(request),
    },
    request,
  );
}
