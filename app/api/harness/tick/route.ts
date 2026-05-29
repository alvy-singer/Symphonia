import { proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export async function POST(request: Request) {
  const url = new URL(request.url);
  return proxyToSymphoniaService(
    `/api/harness/tick${url.search}`,
    { method: "POST" },
    request,
  );
}
