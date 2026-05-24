import { jsonBody, proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function GET() {
  return proxyToSymphoniaService("/api/repositories");
}

export async function POST(request: Request) {
  return proxyToSymphoniaService("/api/repositories", {
    method: "POST",
    body: await jsonBody(request),
  });
}
