import { NextResponse } from "next/server";
import { listRepositoryTasks } from "@/lib/server/task-store";

export const runtime = "nodejs";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ repoKey: string }> },
) {
  const { repoKey } = await params;
  const tasks = await listRepositoryTasks(repoKey);
  return NextResponse.json({ tasks });
}

