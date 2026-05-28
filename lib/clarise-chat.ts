export type ClariseProviderId =
  | "codex_app_server"
  | "claude_code"
  | "gemini"
  | "cursor";

export type ClariseModelProfile = "balanced" | "quality" | "budget";

export type ClariseArtifactKind =
  | "codebase_map"
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
  codebase_map: ["title"],
  milestone: ["title", "goal"],
  requirements: ["title", "requirement", "milestone"],
  plan: ["title", "plan", "milestone"],
  decision: ["title", "decision", "milestone"],
  task_brief: ["title", "goal"],
};

const CHILD_KINDS = new Set<ClariseArtifactKind>(["requirements", "plan", "decision"]);

const KIND_LABELS: Record<ClariseArtifactKind, string> = {
  codebase_map: "codebase map",
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

export function normalizeClariseModelProfile(value: unknown): ClariseModelProfile {
  if (value === "quality" || value === "budget") return value;
  return "balanced";
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
      "I can help run a planning loop by creating private milestones, requirements, plans, decisions, and task briefs. Send a concrete goal or use a slash command and I will save the right workspace artifacts.",
    artifactDrafts: [],
    missingFields: [],
  };
}

export function normalizeClarisePlan(value: unknown): ClarisePlan | null {
  if (!isRecord(value)) return null;

  const artifactDrafts = Array.isArray(value.artifactDrafts)
    ? value.artifactDrafts.flatMap(normalizeArtifactDraft)
    : [];
  const missingFields = Array.isArray(value.missingFields)
    ? value.missingFields.flatMap(normalizeMissingField)
    : [];
  const assistantText =
    stringValue(value.assistantText) ||
    (artifactDrafts.length > 0 ? createdText(artifactDrafts) : "") ||
    (missingFields.length > 0 ? missingText(missingFields) : "");

  if (!assistantText && artifactDrafts.length === 0 && missingFields.length === 0) {
    return null;
  }

  return {
    assistantText:
      assistantText ||
      "I can create private milestones, requirements, plans, decisions, and task briefs.",
    artifactDrafts,
    missingFields,
  };
}

function latestUserMessage(messages: ClariseChatMessage[]): string {
  return [...messages].reverse().find((message) => message.role === "user")?.content ?? "";
}

function parseRequestedDrafts(prompt: string): ParsedDraft[] {
  const slashCommand = parseSlashCommand(prompt);
  if (slashCommand.length > 0) return slashCommand;

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

function parseSlashCommand(prompt: string): ParsedDraft[] {
  const match = prompt.trim().match(/^(\/[a-z0-9:-]+)(?:\s+([\s\S]*))?$/i);
  if (!match) return [];

  const { command, details } = normalizeSlashInvocation(
    match[1].toLowerCase(),
    match[2]?.trim() ?? "",
  );
  const title = fieldValue(details, "title") ?? plainDetails(details);
  const goal = fieldValue(details, "goal") ?? plainDetails(details);
  const context = fieldValue(details, "context");
  const milestone = fieldValue(details, "milestone");

  if (command === "/codebase") {
    return [
      {
        kind: "codebase_map",
        title: title ?? "Codebase map",
        context,
      },
    ];
  }

  if (command === "/milestone") {
    return [{ kind: "milestone", title, goal, context }];
  }

  if (command === "/requirement" || command === "/requirements") {
    return [
      {
        kind: "requirements",
        title,
        requirement: fieldValue(details, "requirement") ?? plainDetails(details),
        milestone,
        context,
      },
    ];
  }

  if (command === "/plan") {
    return [
      {
        kind: "plan",
        title,
        plan: fieldValue(details, "plan") ?? plainDetails(details),
        milestone,
        context,
      },
    ];
  }

  if (command === "/decision") {
    return [
      {
        kind: "decision",
        title,
        decision: fieldValue(details, "decision") ?? plainDetails(details),
        milestone,
        context,
      },
    ];
  }

  if (command === "/task-brief" || command === "/task") {
    return [{ kind: "task_brief", title, goal, context }];
  }

  if (command === "/workflow") {
    return [
      {
        kind: "task_brief",
        title: fieldValue(details, "title") ?? "Set up WORKFLOW.md",
        goal:
          fieldValue(details, "goal") ??
          plainDetails(details) ??
          "Create a private planning brief for repository rules before any file write is proposed.",
        context:
          context ??
          "Clarise v1 prepares private planning artifacts only; it does not write GitHub files.",
      },
    ];
  }

  if (command === "/new-project") {
    return [
      {
        kind: "milestone",
        title: fieldValue(details, "milestone") ?? "Project foundation",
        goal,
        context,
      },
      {
        kind: "requirements",
        title: fieldValue(details, "requirement title") ?? "Must-have scope",
        requirement: fieldValue(details, "requirement"),
        context,
      },
      {
        kind: "plan",
        title: fieldValue(details, "plan title") ?? "Roadmap",
        plan: fieldValue(details, "plan"),
        context,
      },
      {
        kind: "task_brief",
        title: fieldValue(details, "task title") ?? "First execution slice",
        goal: fieldValue(details, "task goal") ?? fieldValue(details, "task brief"),
        context,
      },
    ];
  }

  if (command === "/discuss-phase") {
    return [
      {
        kind: "decision",
        title: title ?? "Phase implementation decisions",
        decision: fieldValue(details, "decision") ?? plainDetails(details),
        milestone,
        context,
      },
    ];
  }

  if (command === "/plan-phase") {
    return [
      {
        kind: "plan",
        title: title ?? "Phase plan",
        plan: fieldValue(details, "plan") ?? plainDetails(details),
        milestone,
        context,
      },
    ];
  }

  if (command === "/execute-phase") {
    return [
      {
        kind: "task_brief",
        title: title ?? "Phase execution",
        goal,
        context,
      },
    ];
  }

  if (command === "/verify-work") {
    return [
      {
        kind: "task_brief",
        title: title ?? "Verification checklist",
        goal,
        context,
      },
    ];
  }

  if (command === "/ship") {
    return [{ kind: "task_brief", title: title ?? "Ship checklist", goal, context }];
  }

  return [];
}

function normalizeSlashInvocation(
  rawCommand: string,
  rawDetails: string,
): { command: string; details: string } {
  return {
    command: rawCommand.replace(/:/g, "-"),
    details: rawDetails,
  };
}

function parseBatchLines(prompt: string): ParsedDraft[] {
  return prompt
    .split(/\r?\n/)
    .map((line) => line.trim())
    .flatMap((line): ParsedDraft[] => {
      const match = line.match(
        /^(codebase|codebase\s*map|milestone|requirement|requirements|plan|decision|task\s*brief|task):\s*(.+)$/i,
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
  if (normalized === "codebase" || normalized === "codebase map") return "codebase_map";
  if (normalized === "decision") return "decision";
  if (normalized === "milestone") return "milestone";
  if (normalized === "requirement" || normalized === "requirements") return "requirements";
  if (normalized === "plan") return "plan";
  return "task_brief";
}

function requestedKind(prompt: string): ClariseArtifactKind | null {
  if (prompt.includes("codebase")) return "codebase_map";
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

function plainDetails(details: string): string | undefined {
  const value = details.trim();
  if (!value || /^[a-z][a-z ]*:/im.test(value)) return undefined;
  return value;
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

  if (draft.kind === "codebase_map") {
    return {
      kind: "codebase_map",
      title,
      body: [
        "# Codebase Map",
        "",
        "## Purpose",
        draft.context?.trim() || "Clarise captured the first private codebase map for this repository.",
        "",
        "## Entry points",
        "- Identify the primary app, service, and workspace entry points.",
        "",
        "## Important paths",
        "- Add repository paths as the workspace is reviewed.",
        "",
        "## Data and state",
        "- Capture durable workspace files, task files, and local/private run state boundaries.",
        "",
        "## Open questions",
        "- Which areas should Clarise inspect before implementation work starts?",
      ].join("\n"),
      metadata,
      confirmation: `Created private codebase map "${title}".`,
    };
  }

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

function normalizeArtifactDraft(value: unknown): ClariseArtifactDraft[] {
  if (!isRecord(value)) return [];
  const kind = normalizeKind(value.kind);
  const title = stringValue(value.title);
  const body = stringValue(value.body);
  const confirmation = stringValue(value.confirmation);
  if (!kind || !title || !body || !confirmation) return [];

  const rawMetadata = isRecord(value.metadata) ? value.metadata : {};

  return [
    {
      kind,
      title,
      body,
      confirmation,
      metadata: {
        ...rawMetadata,
        title,
        status: stringValue(rawMetadata.status) || "draft",
        source: stringValue(rawMetadata.source) || "clarise_chat",
        private: true,
        provider_created_at:
          stringValue(rawMetadata.provider_created_at) || new Date().toISOString(),
      },
      parentMilestoneId: stringValue(value.parentMilestoneId),
      linkToBatchMilestone: value.linkToBatchMilestone === true,
    },
  ];
}

function normalizeMissingField(value: unknown): ClariseMissingField[] {
  if (!isRecord(value)) return [];
  const kind = normalizeKind(value.kind);
  const field = stringValue(value.field);
  if (!kind || !field) return [];
  return [{ kind, field }];
}

function normalizeKind(value: unknown): ClariseArtifactKind | null {
  if (
    value === "milestone" ||
    value === "codebase_map" ||
    value === "requirements" ||
    value === "plan" ||
    value === "decision" ||
    value === "task_brief"
  ) {
    return value;
  }

  return null;
}

function stringValue(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed || undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
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
