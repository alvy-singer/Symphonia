import { SERVICE_URL } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

interface RunProgressEvent {
  id: string;
  runId?: string;
  taskKey?: string;
  state?: string;
  displayStep?: string;
  displayMessage?: string;
  reviewBranch?: string;
  curatedSummaryPath?: string;
  updatedAt?: string;
}

const TERMINAL_STATES = new Set(["completed", "failed", "canceled"]);

export async function GET(
  request: Request,
  { params }: { params: Promise<{ repoKey: string; taskKey: string; runId: string }> },
) {
  const { repoKey, taskKey, runId } = await params;
  const url = new URL(request.url);
  let cursor = url.searchParams.get("after") ?? request.headers.get("last-event-id") ?? undefined;
  const encoder = new TextEncoder();
  let cancelled = false;

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const send = (chunk: string) => controller.enqueue(encoder.encode(chunk));

      try {
        send("retry: 3000\n\n");

        for (let attempt = 0; attempt < 180 && !cancelled; attempt += 1) {
          const events = await fetchProgressEvents(repoKey, taskKey, runId, cursor);
          let sawTerminal = false;

          for (const event of events) {
            if (!event.id) continue;
            cursor = event.id;
            sawTerminal = sawTerminal || TERMINAL_STATES.has(event.state ?? "");
            send(formatRunProgressEvent(event));
          }

          if (sawTerminal) break;

          send(`: heartbeat ${new Date().toISOString()}\n\n`);
          await sleep(2000);
        }
      } catch {
        send(": stream closed\n\n");
      } finally {
        controller.close();
      }
    },
    cancel() {
      cancelled = true;
    },
  });

  return new Response(stream, {
    headers: {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-store, no-transform",
      connection: "keep-alive",
      "x-accel-buffering": "no",
    },
  });
}

async function fetchProgressEvents(
  repoKey: string,
  taskKey: string,
  runId: string,
  after?: string,
): Promise<RunProgressEvent[]> {
  const query = after ? `?after=${encodeURIComponent(after)}` : "";
  const response = await fetch(
    `${SERVICE_URL}/api/repositories/${encodeURIComponent(repoKey)}/tasks/${encodeURIComponent(
      taskKey,
    )}/runs/${encodeURIComponent(runId)}/events${query}`,
    { cache: "no-store" },
  );

  if (!response.ok) return [];

  const payload = (await response.json().catch(() => ({}))) as {
    events?: RunProgressEvent[];
  };

  return Array.isArray(payload.events) ? payload.events : [];
}

function formatRunProgressEvent(event: RunProgressEvent): string {
  const data = {
    runId: event.runId,
    taskKey: event.taskKey,
    state: event.state,
    displayStep: event.displayStep,
    displayMessage: event.displayMessage,
    reviewBranch: event.reviewBranch,
    curatedSummaryPath: event.curatedSummaryPath,
    updatedAt: event.updatedAt,
  };

  return [
    `id: ${event.id}`,
    "event: run-progress",
    `data: ${JSON.stringify(data)}`,
    "",
    "",
  ].join("\n");
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
