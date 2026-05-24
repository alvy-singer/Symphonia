import { proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function GET() {
  return proxyToSymphoniaService("/api/github/repositories");
}
