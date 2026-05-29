import { proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function POST(request: Request) {
  const url = new URL(request.url);
  return proxyToSymphoniaService(
    `/api/harness/daemon/tick${url.search}`,
    { method: "POST" },
    request,
  );
}
