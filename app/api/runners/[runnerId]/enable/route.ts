import { proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ runnerId: string }> },
) {
  const { runnerId } = await params;

  return proxyToSymphoniaService(
    `/api/runners/${encodeURIComponent(runnerId)}/enable`,
    { method: "POST" },
    request,
  );
}
