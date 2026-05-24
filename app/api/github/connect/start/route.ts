import { proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function POST() {
  return proxyToSymphoniaService("/api/github/connect/start", {
    method: "POST",
    body: "{}",
  });
}
