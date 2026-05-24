import { NextResponse } from "next/server";
import { applyTaskEvent } from "@/lib/server/task-store";
import type { TaskLifecycleEvent } from "@/lib/task-model";

export const runtime = "nodejs";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ repoKey: string; taskKey: string }> },
) {
  const { repoKey, taskKey } = await params;
  const payload = (await request.json()) as {
    event?: TaskLifecycleEvent;
    params?: Record<string, unknown>;
  };

  if (!payload.event) {
    return NextResponse.json({ error: "Missing lifecycle event" }, { status: 400 });
  }

  const task = await applyTaskEvent(
    repoKey,
    decodeURIComponent(taskKey),
    payload.event,
    payload.params ?? {},
  );
  return NextResponse.json({ task });
}
