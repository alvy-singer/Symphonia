import { jsonBody, proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function POST(request: Request) {
  return proxyToSymphoniaService("/api/github/repositories/workspace", {
    method: "POST",
    body: await jsonBody(request),
  });
}
