import { jsonBody, proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ repoKey: string; pageId: string }> },
) {
  const { repoKey, pageId } = await params;
  return proxyToSymphoniaService(
    `/api/repositories/${encodeURIComponent(repoKey)}/pages/${encodeURIComponent(pageId)}`,
  );
}

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ repoKey: string; pageId: string }> },
) {
  const { repoKey, pageId } = await params;
  return proxyToSymphoniaService(
    `/api/repositories/${encodeURIComponent(repoKey)}/pages/${encodeURIComponent(pageId)}`,
    {
      method: "PATCH",
      body: await jsonBody(request),
    },
    request,
  );
}

export async function DELETE(
  request: Request,
  { params }: { params: Promise<{ repoKey: string; pageId: string }> },
) {
  const { repoKey, pageId } = await params;
  const url = new URL(request.url);
  return proxyToSymphoniaService(
    `/api/repositories/${encodeURIComponent(repoKey)}/pages/${encodeURIComponent(
      pageId,
    )}${url.search}`,
    { method: "DELETE" },
    request,
  );
}
