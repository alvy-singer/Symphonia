import { proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export async function POST(request: Request) {
  const url = new URL(request.url);
  return proxyToSymphoniaService(
    `/api/harness/reconcile${url.search}`,
    { method: "POST" },
    request,
  );
}
