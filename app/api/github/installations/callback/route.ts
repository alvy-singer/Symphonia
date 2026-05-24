import { NextResponse } from "next/server";
import { proxyToSymphoniaService } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const installationId = url.searchParams.get("installation_id");
  const setupAction = url.searchParams.get("setup_action");
  const repoKey =
    url.searchParams.get("repo") ?? url.searchParams.get("repoKey") ?? url.searchParams.get("state");

  if (installationId) {
    await proxyToSymphoniaService("/api/github/installations/complete", {
      method: "POST",
      body: JSON.stringify({
        installation_id: installationId,
        setup_action: setupAction,
      }),
    });
  }

  const redirectPath = repoKey ? `/r/${encodeURIComponent(repoKey)}/settings` : "/";
  const redirectUrl = new URL(redirectPath, url.origin);
  redirectUrl.searchParams.set("github", installationId ? "installed" : "install-canceled");

  return NextResponse.redirect(redirectUrl);
}
