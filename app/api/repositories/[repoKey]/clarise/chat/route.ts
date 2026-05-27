import { NextResponse } from "next/server";
import {
  normalizeClariseProvider,
  planClariseResponse,
  type ClariseArtifactDraft,
  type ClariseChatMessage,
  type ClariseProviderId,
} from "@/lib/clarise-chat";
import { serviceJson } from "@/lib/server/symphonia-service";

export const runtime = "nodejs";

type ServiceArtifact = {
  type: string;
  id: string;
  title: string;
  status: string;
  path: string;
};

type ServiceArtifactResponse = {
  artifact: ServiceArtifact;
};

type StreamEvent =
  | { type: "message_delta"; text: string }
  | { type: "tool_call"; name: "create_private_artifact"; artifactKind: string; title: string }
  | {
      type: "artifact_result";
      artifact: {
        kind: string;
        type: string;
        id: string;
        title: string;
        status: string;
        href: string;
      };
    }
  | { type: "artifact_failure"; artifactKind: string; title: string; error: string }
  | { type: "missing_fields"; fields: { kind: string; field: string }[] }
  | { type: "done"; createdCount: number; failedCount: number };

const PROVIDERS: Record<
  ClariseProviderId,
  { label: string; connected: () => boolean; setup: string }
> = {
  codex_app_server: {
    label: "Codex",
    connected: () => true,
    setup: "/settings",
  },
  claude_code: {
    label: "Claude Code",
    connected: () => process.env.SYMPHONIA_CLAUDE_CODE_CONNECTED === "true",
    setup: "/settings",
  },
  gemini: {
    label: "Gemini",
    connected: () => process.env.SYMPHONIA_GEMINI_CONNECTED === "true",
    setup: "/settings",
  },
  cursor: {
    label: "Cursor",
    connected: () => process.env.SYMPHONIA_CURSOR_CONNECTED === "true",
    setup: "/settings",
  },
};

export async function POST(
  request: Request,
  { params }: { params: Promise<{ repoKey: string }> },
) {
  const { repoKey } = await params;
  const payload = (await request.json().catch(() => ({}))) as {
    provider?: unknown;
    messages?: ClariseChatMessage[];
  };
  const provider = normalizeClariseProvider(payload.provider);
  const providerConfig = PROVIDERS[provider];

  if (!providerConfig.connected()) {
    return NextResponse.json(
      {
        code: "provider_not_connected",
        error: `${providerConfig.label} is not connected.`,
        provider,
        providerSetupHref: `/r/${repoKey.toLowerCase()}${providerConfig.setup}`,
      },
      { status: 409 },
    );
  }

  const plan = planClariseResponse(Array.isArray(payload.messages) ? payload.messages : []);

  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const emit = (event: StreamEvent) => {
        controller.enqueue(encoder.encode(`data: ${JSON.stringify(event)}\n\n`));
      };

      let createdCount = 0;
      let failedCount = 0;
      let batchMilestoneId: string | undefined;

      emit({ type: "message_delta", text: plan.assistantText });
      if (plan.missingFields.length > 0) {
        emit({ type: "missing_fields", fields: plan.missingFields });
      }

      for (const draft of plan.artifactDrafts) {
        emit({
          type: "tool_call",
          name: "create_private_artifact",
          artifactKind: draft.kind,
          title: draft.title,
        });

        try {
          const artifact = await createPrivateArtifact(repoKey, provider, draft, batchMilestoneId);
          if (draft.kind === "milestone") batchMilestoneId = artifact.id;
          createdCount += 1;
          emit({
            type: "artifact_result",
            artifact: {
              kind: draft.kind,
              type: artifact.type,
              id: artifact.id,
              title: artifact.title,
              status: artifact.status,
              href: `/r/${repoKey.toLowerCase()}/workspace/${encodeURIComponent(
                artifact.type,
              )}/${encodeURIComponent(artifact.id)}`,
            },
          });
        } catch (error) {
          failedCount += 1;
          emit({
            type: "artifact_failure",
            artifactKind: draft.kind,
            title: draft.title,
            error: error instanceof Error ? error.message : "Could not create artifact.",
          });
        }
      }

      emit({ type: "done", createdCount, failedCount });
      controller.close();
    },
  });

  return new Response(stream, {
    headers: {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

async function createPrivateArtifact(
  repoKey: string,
  provider: ClariseProviderId,
  draft: ClariseArtifactDraft,
  batchMilestoneId?: string,
): Promise<ServiceArtifact> {
  if (draft.linkToBatchMilestone && !batchMilestoneId) {
    throw new Error("Parent milestone was not created.");
  }

  const relatedMilestone = draft.parentMilestoneId ?? (draft.linkToBatchMilestone ? batchMilestoneId : undefined);
  const endpoint = endpointForKind(draft.kind);
  const payload = await serviceJson<ServiceArtifactResponse>(
    `/api/repositories/${encodeURIComponent(repoKey)}/spec-workspace/${endpoint}`,
    {
      method: "POST",
      body: JSON.stringify({
        ...draft.metadata,
        provider,
        related_milestone: relatedMilestone,
        title: draft.title,
        body: draft.body,
      }),
    },
  );

  return payload.artifact;
}

function endpointForKind(kind: ClariseArtifactDraft["kind"]): string {
  switch (kind) {
    case "milestone":
      return "milestones";
    case "requirements":
      return "requirements";
    case "plan":
      return "plans";
    case "decision":
      return "decisions";
    case "task_brief":
      return "task-briefs";
  }
}
