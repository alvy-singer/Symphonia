import { jsonBody, proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ repoKey: string; milestoneId: string }> },
) {
  const { repoKey, milestoneId } = await params;
  return proxyToSymphoniaService(
    `/api/repositories/${encodeURIComponent(repoKey)}/clarise/milestones/${encodeURIComponent(
      milestoneId,
    )}/requirements`,
    {
      method: "POST",
      body: await jsonBody(request),
    },
  );
}
