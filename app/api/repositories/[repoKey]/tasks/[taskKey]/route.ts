import { NextResponse } from "next/server";
import {
  getRepositoryTask,
  patchRepositoryTask,
} from "@/lib/server/task-store";

export const runtime = "nodejs";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ repoKey: string; taskKey: string }> },
) {
  const { repoKey, taskKey } = await params;
  const task = await getRepositoryTask(repoKey, decodeURIComponent(taskKey));
  if (!task) return NextResponse.json({ error: "Task not found" }, { status: 404 });
  return NextResponse.json({ task });
}

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ repoKey: string; taskKey: string }> },
) {
  const { repoKey, taskKey } = await params;
  const payload = await request.json();
  const task = await patchRepositoryTask(repoKey, decodeURIComponent(taskKey), payload);
  return NextResponse.json({ task });
}

