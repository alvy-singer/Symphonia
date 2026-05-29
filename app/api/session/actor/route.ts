import { proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function GET(request: Request) {
  return proxyToSymphoniaService("/api/session/actor", {}, request);
}
