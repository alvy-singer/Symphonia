export type ClariseProviderId =
  | "codex_app_server"
  | "claude_code"
  | "gemini"
  | "cursor";

export type ClariseArtifactKind =
  | "milestone"
  | "requirements"
  | "plan"
  | "decision"
  | "task_brief";

export type ClariseChatRole = "user" | "assistant" | "clarise";

export interface ClariseChatMessage {
  role: ClariseChatRole;
  content: string;
}

export interface ClariseArtifactDraft {
  kind: ClariseArtifactKind;
  title: string;
  body: string;
  metadata: Record<string, unknown>;
  confirmation: string;
  parentMilestoneId?: string;
  linkToBatchMilestone?: boolean;
}

export interface ClariseMissingField {
  kind: ClariseArtifactKind;
  field: string;
}

export interface ClarisePlan {
  assistantText: string;
  artifactDrafts: ClariseArtifactDraft[];
  missingFields: ClariseMissingField[];
}

type ParsedDraft = {
  kind: ClariseArtifactKind;
  title?: string;
  goal?: string;
  requirement?: string;
  plan?: string;
  decision?: string;
  milestone?: string;
  context?: string;
};

const REQUIRED_FIELDS: Record<ClariseArtifactKind, string[]> = {
  milestone: ["title", "goal"],
  requirements: ["title", "requirement", "milestone"],
  plan: ["title", "plan", "milestone"],
  decision: ["title", "decision", "milestone"],
  task_brief: ["title", "goal"],
};

const CHILD_KINDS = new Set<ClariseArtifactKind>(["requirements", "plan", "decision"]);

const KIND_LABELS: Record<ClariseArtifactKind, string> = {
  milestone: "milestone",
  requirements: "requirement",
  plan: "plan",
  decision: "decision",
  task_brief: "task brief",
};

export function normalizeClariseProvider(value: unknown): ClariseProviderId {
  if (value === "claude_code" || value === "gemini" || value === "cursor") return value;
  return "codex_app_server";
}

export function planClariseResponse(messages: ClariseChatMessage[]): ClarisePlan {
  const prompt = latestUserMessage(messages);
  const parsed = parseRequestedDrafts(prompt);
  const hasBatchMilestone = parsed.some((draft) => draft.kind === "milestone");
  const missingFields = parsed.flatMap((draft) => missingRequiredFields(draft, hasBatchMilestone));

  if (parsed.length > 0 && missingFields.length === 0) {
    const artifactDrafts = parsed.map((draft) => toArtifactDraft(draft, hasBatchMilestone));
    return {
      assistantText: createdText(artifactDrafts),
      artifactDrafts,
      missingFields: [],
    };
  }

  if (missingFields.length > 0) {
    return {
      assistantText: missingText(missingFields),
      artifactDrafts: [],
      missingFields,
    };
  }

  return {
    assistantText:
      "I can create private milestones, requirements, plans, decisions, and task briefs. Send the missing fields and I will save the artifact.",
    artifactDrafts: [],
    missingFields: [],
  };
}

function latestUserMessage(messages: ClariseChatMessage[]): string {
  return [...messages].reverse().find((message) => message.role === "user")?.content ?? "";
}

function parseRequestedDrafts(prompt: string): ParsedDraft[] {
  const batch = parseBatchLines(prompt);
  if (batch.length > 0) return batch;

  const lower = prompt.toLowerCase();

  if (lower.includes("workflow.md") || lower.includes("workflow")) {
    return [
      {
        kind: "task_brief",
        title: fieldValue(prompt, "title") ?? "Set up WORKFLOW.md",
        goal:
          fieldValue(prompt, "goal") ??
          "Create a private planning brief for repository rules before any file write is proposed.",
        milestone: fieldValue(prompt, "milestone"),
        context:
          fieldValue(prompt, "context") ??
          "Clarise v1 prepares private planning artifacts only; it does not write GitHub files.",
      },
    ];
  }

  const kind = requestedKind(lower);
  if (!kind) return [];

  return [
    {
      kind,
      title: fieldValue(prompt, "title") ?? inlineTitle(prompt, kind),
      goal: fieldValue(prompt, "goal"),
      requirement: fieldValue(prompt, "requirement"),
      plan: fieldValue(prompt, "plan"),
      decision: fieldValue(prompt, "decision"),
      milestone: fieldValue(prompt, "milestone"),
      context: fieldValue(prompt, "context"),
    },
  ];
}

function parseBatchLines(prompt: string): ParsedDraft[] {
  return prompt
    .split(/\r?\n/)
    .map((line) => line.trim())
    .flatMap((line): ParsedDraft[] => {
      const match = line.match(
        /^(milestone|requirement|requirements|plan|decision|task\s*brief|task):\s*(.+)$/i,
      );
      if (!match) return [];

      const kind = kindFromBatchLabel(match[1]);
      const parts = match[2].split("|").map((part) => part.trim()).filter(Boolean);
      const title = parts.shift();
      const fields = parts.reduce<Record<string, string>>((acc, part) => {
        const fieldMatch = part.match(/^([a-z ]+):\s*(.+)$/i);
        if (!fieldMatch) return acc;
        acc[fieldMatch[1].trim().toLowerCase()] = fieldMatch[2].trim();
        return acc;
      }, {});

      return [
        {
          kind,
          title,
          goal: fields.goal,
          requirement: fields.requirement ?? fields.requirements,
          plan: fields.plan,
          decision: fields.decision,
          milestone: fields.milestone,
          context: fields.context,
        },
      ];
    });
}

function kindFromBatchLabel(label: string): ClariseArtifactKind {
  const normalized = label.toLowerCase().replace(/\s+/g, " ");
  if (normalized === "decision") return "decision";
  if (normalized === "milestone") return "milestone";
  if (normalized === "requirement" || normalized === "requirements") return "requirements";
  if (normalized === "plan") return "plan";
  return "task_brief";
}

function requestedKind(prompt: string): ClariseArtifactKind | null {
  if (prompt.includes("requirement")) return "requirements";
  if (prompt.includes("decision")) return "decision";
  if (prompt.includes("milestone")) return "milestone";
  if (prompt.includes("plan")) return "plan";
  if (prompt.includes("task brief") || prompt.includes("quick task") || prompt.includes("task")) {
    return "task_brief";
  }
  return null;
}

function fieldValue(prompt: string, field: string): string | undefined {
  const escaped = field.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = prompt.match(new RegExp(`(?:^|\\n)\\s*${escaped}\\s*:\\s*(.+)`, "i"));
  const value = match?.[1]?.trim();
  return value || undefined;
}

function inlineTitle(prompt: string, kind: ClariseArtifactKind): string | undefined {
  const label = KIND_LABELS[kind].replace(" ", "\\s*");
  const match = prompt.match(new RegExp(`${label}\\s*:\\s*([^\\n|]+)`, "i"));
  const value = match?.[1]?.trim();
  return value || undefined;
}

function missingRequiredFields(draft: ParsedDraft, hasBatchMilestone: boolean): ClariseMissingField[] {
  return REQUIRED_FIELDS[draft.kind].flatMap((field) => {
    if (field === "milestone" && hasBatchMilestone) return [];
    const value = draft[field as keyof ParsedDraft];
    return typeof value === "string" && value.trim() ? [] : [{ kind: draft.kind, field }];
  });
}

function toArtifactDraft(draft: ParsedDraft, hasBatchMilestone: boolean): ClariseArtifactDraft {
  const title = requiredString(draft.title);
  const now = new Date().toISOString();
  const parentMilestoneId = draft.milestone?.trim() || undefined;
  const linkToBatchMilestone = !parentMilestoneId && CHILD_KINDS.has(draft.kind) && hasBatchMilestone;
  const metadata = {
    title,
    status: "draft",
    source: "clarise_chat",
    private: true,
    provider_created_at: now,
    related_milestone: parentMilestoneId,
  };

  if (draft.kind === "decision") {
    const decision = requiredString(draft.decision);
    return withParent({
      kind: "decision",
      title,
      body: [
        `# Decision - ${title}`,
        "",
        "## Context",
        draft.context?.trim() || "Clarise captured this as a private planning decision.",
        "",
        "## Decision",
        decision,
        "",
        "## Consequences",
        "- Kept private in the Symphonia workspace.",
        "- No GitHub file, pull request, coding run, or evidence publish is started.",
      ].join("\n"),
      metadata,
      confirmation: `Created private decision "${title}".`,
    }, parentMilestoneId, linkToBatchMilestone);
  }

  if (draft.kind === "requirements") {
    const requirement = requiredString(draft.requirement);
    return withParent({
      kind: "requirements",
      title,
      body: [
        `# Requirement - ${title}`,
        "",
        "## Requirement",
        requirement,
        "",
        "## Validation criteria",
        draft.context?.trim() || "- Confirm this requirement before implementation starts.",
        "",
        "## Safety boundary",
        "- Clarise v1 saves this as a private planning artifact only.",
      ].join("\n"),
      metadata,
      confirmation: `Created private requirement "${title}".`,
    }, parentMilestoneId, linkToBatchMilestone);
  }

  if (draft.kind === "plan") {
    const plan = requiredString(draft.plan);
    return withParent({
      kind: "plan",
      title,
      body: [
        `# Plan - ${title}`,
        "",
        "## Plan",
        plan,
        "",
        "## Validation",
        draft.context?.trim() || "- Review this plan before turning it into execution work.",
        "",
        "## Safety boundary",
        "- Clarise v1 does not start agent runs from this plan.",
      ].join("\n"),
      metadata,
      confirmation: `Created private plan "${title}".`,
    }, parentMilestoneId, linkToBatchMilestone);
  }

  if (draft.kind === "milestone") {
    const goal = requiredString(draft.goal);
    return {
      kind: "milestone",
      title,
      body: [
        `# Milestone - ${title}`,
        "",
        "## Goal",
        goal,
        "",
        "## Why this matters",
        draft.context?.trim() || "Clarise captured this as private project memory.",
        "",
        "## Scope",
        "- Define the durable planning context before implementation work starts.",
        "",
        "## Acceptance criteria",
        "- [ ] The milestone can anchor requirements, plans, decisions, and task briefs.",
      ].join("\n"),
      metadata,
      confirmation: `Created private milestone "${title}".`,
    };
  }

  const goal = requiredString(draft.goal);
  return {
    kind: "task_brief",
    title,
    body: [
      `# ${title}`,
      "",
      "## Goal",
      goal,
      "",
      "## Context",
      draft.context?.trim() || "Clarise captured this as a standalone private task brief.",
      "",
      "## Acceptance criteria",
      "- [ ] The brief is specific enough for later review.",
      "- [ ] Follow-up implementation is explicitly approved before any coding run.",
      "",
      "## Review expectations",
      "- Review this private brief in the workspace before turning it into execution work.",
      "",
      "## Safety boundary",
      "- Clarise v1 does not start agent runs, open PRs, publish evidence, or write GitHub files.",
    ].join("\n"),
    metadata: { ...metadata, related_milestone: parentMilestoneId },
    parentMilestoneId,
    confirmation: `Created private task brief "${title}".`,
  };
}

function withParent(
  draft: ClariseArtifactDraft,
  parentMilestoneId: string | undefined,
  linkToBatchMilestone: boolean,
): ClariseArtifactDraft {
  return {
    ...draft,
    parentMilestoneId,
    linkToBatchMilestone,
  };
}

function requiredString(value: string | undefined): string {
  if (!value?.trim()) throw new Error("Required Clarise field was missing.");
  return value.trim();
}

function createdText(drafts: ClariseArtifactDraft[]): string {
  if (drafts.length === 1) return `Saving ${KIND_LABELS[drafts[0].kind]}.`;
  return `Saving ${drafts.length} private docs.`;
}

function missingText(fields: ClariseMissingField[]): string {
  const grouped = fields.reduce<Record<string, string[]>>((acc, item) => {
    const label = KIND_LABELS[item.kind];
    acc[label] = acc[label] ?? [];
    acc[label].push(item.field);
    return acc;
  }, {});

  const needed = Object.entries(grouped)
    .map(([kind, items]) => `${kind}: ${items.join(", ")}`)
    .join("; ");

  return `Missing fields: ${needed}.`;
}
