import { proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function POST(
  request: Request,
  {
    params,
  }: {
    params: Promise<{ repoKey: string; artifactType: string; artifactId: string; exportId: string }>;
  },
) {
  const { repoKey, artifactType, artifactId, exportId } = await params;
  return proxyToSymphoniaService(
    `/api/repositories/${encodeURIComponent(repoKey)}/private-workspace/artifacts/${encodeURIComponent(
      artifactType,
    )}/${encodeURIComponent(artifactId)}/exports/${encodeURIComponent(exportId)}/refresh`,
    { method: "POST" },
    request,
  );
}
