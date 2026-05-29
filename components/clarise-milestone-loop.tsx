"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";
import {
  AlertTriangle,
  ArrowDown,
  ArrowRight,
  ArrowUp,
  CheckCircle2,
  Circle,
  ClipboardList,
  ExternalLink,
  FileText,
  ListChecks,
  MessageSquareText,
  Milestone,
  PenLine,
  Plus,
  RefreshCcw,
  ShieldCheck,
  X,
} from "lucide-react";
import type {
  SpecArtifact,
  SpecArtifactStatus,
  SpecArtifactSummary,
  SpecWorkspacePayload,
} from "@/lib/repository-model";
import { cn } from "@/lib/utils";

type LinkedArtifacts = {
  discussion?: SpecArtifact | null;
  requirements?: SpecArtifact | null;
  plan?: SpecArtifact | null;
};

type Question = {
  id: string;
  question: string;
};

type LoopPayload = {
  milestone?: SpecArtifact;
  discussion?: SpecArtifact;
  requirements?: SpecArtifact;
  plan?: SpecArtifact;
  decision?: SpecArtifact;
  questions?: Question[];
  approved?: boolean;
  error?: string;
};

type TaskProposalItem = {
  id: string;
  selected?: boolean;
  title: string;
  body?: string;
  priority: string;
  depends_on: string[];
  goal: string;
  implementation_notes: string[];
  acceptance_criteria: string[];
  review_expectations: string[];
  related_artifacts: string[];
  linked_files?: string[];
  automation_readiness?: AutomationReadiness;
};

type AutomationReadiness = {
  ready: boolean;
  blockers: string[];
  warnings: string[];
};

type TaskProposalCreatePayload = {
  selectedProposalItemIds: string[];
  items: TaskProposalItem[];
};

type GeneratedTask = {
  key: string;
  title: string;
  status: string;
  dependsOn?: string[];
};

type TaskProposalPayload = {
  proposal?: SpecArtifact;
  items?: TaskProposalItem[];
  tasks?: GeneratedTask[];
  createdTasks?: string[];
  createdCount?: number;
  skipped?: { title: string; reason: string }[];
  generationId?: string;
  blockers?: string[];
  warnings?: string[];
  automationReadiness?: AutomationReadiness;
  nextStep?: string;
  taskBoard?: {
    sourceMilestone?: string;
    createdTasks?: string[];
  };
  error?: string;
};

const QUESTIONS: Question[] = [
  { id: "accomplish", question: "What should this milestone accomplish?" },
  { id: "why", question: "Why does it matter?" },
  { id: "include", question: "What should be included?" },
  { id: "exclude", question: "What should be excluded?" },
  { id: "complete", question: "What would make this feel complete?" },
  { id: "codebase", question: "What parts of the codebase are likely involved?" },
  { id: "risks", question: "What risks or unknowns should be tracked?" },
];

const STATUS_LABELS: Record<SpecArtifactStatus, string> = {
  draft: "Draft",
  in_discussion: "In discussion",
  requirements_ready: "Requirements ready",
  plan_ready: "Plan ready",
  ready_for_approval: "Ready for approval",
  approved: "Approved",
  created: "Created",
  archived: "Archived",
};

const STEPS = [
  { key: "draft", label: "Start", icon: Milestone },
  { key: "discussion", label: "Discuss", icon: MessageSquareText },
  { key: "requirements", label: "Requirements", icon: ListChecks },
  { key: "plan", label: "Plan", icon: FileText },
  { key: "approval", label: "Approve plan", icon: ShieldCheck },
  { key: "tasks", label: "Task handoff", icon: ClipboardList },
] as const;

export function ClariseMilestoneLoop({ repoKey }: { repoKey: string }) {
  const router = useRouter();
  const repoSlug = repoKey.toLowerCase();
  const [workspace, setWorkspace] = useState<SpecWorkspacePayload | null>(null);
  const [selectedMilestoneId, setSelectedMilestoneId] = useState<string | null>(null);
  const [milestone, setMilestone] = useState<SpecArtifact | null>(null);
  const [linked, setLinked] = useState<LinkedArtifacts>({});
  const [questions, setQuestions] = useState<Question[]>(QUESTIONS);
  const [title, setTitle] = useState("Untitled milestone");
  const [goal, setGoal] = useState("");
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [decisionTitle, setDecisionTitle] = useState("");
  const [decisionBody, setDecisionBody] = useState("");
  const [taskProposal, setTaskProposal] = useState<TaskProposalPayload | null>(null);
  const [loading, setLoading] = useState(true);
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const milestones = useMemo(() => milestoneSummaries(workspace), [workspace]);

  const loadWorkspace = useCallback(
    async (preferredMilestoneId?: string | null) => {
      setLoading(true);
      setError(null);
      try {
        const nextWorkspace = await fetchWorkspace(repoKey);
        setWorkspace(nextWorkspace);

        const summaries = milestoneSummaries(nextWorkspace);
        const nextSummary =
          summaries.find((item) => item.id === preferredMilestoneId) ??
          summaries.find((item) => item.id === selectedMilestoneId) ??
          summaries.at(-1) ??
          null;

        if (!nextSummary) {
          setSelectedMilestoneId(null);
          setMilestone(null);
          setLinked({});
          setTaskProposal(null);
          return;
        }

        setSelectedMilestoneId(nextSummary.id);
        const nextMilestone = await fetchArtifact(repoKey, "milestone", nextSummary.id);
        setMilestone(nextMilestone);
        setTitle(nextMilestone.title);
        setGoal(sectionFromBody(nextMilestone.body, "Goal"));
        setLinked(await fetchLinkedArtifacts(repoKey, nextMilestone));
        setTaskProposal(await fetchExistingTaskProposal(repoKey, nextMilestone.id));
      } catch (err) {
        setError(err instanceof Error ? err.message : "Could not load workspace");
      } finally {
        setLoading(false);
      }
    },
    [repoKey, selectedMilestoneId],
  );

  useEffect(() => {
    void loadWorkspace();
  }, [loadWorkspace]);

  const runAction = async (
    key: string,
    action: () => Promise<LoopPayload>,
    success: string,
  ) => {
    setPending(key);
    setError(null);
    setNotice(null);
    try {
      const payload = await action();
      if (payload.questions?.length) setQuestions(payload.questions);
      const nextMilestone = payload.milestone;
      if (nextMilestone) {
        setMilestone(nextMilestone);
        setSelectedMilestoneId(nextMilestone.id);
        setTitle(nextMilestone.title);
        setGoal(sectionFromBody(nextMilestone.body, "Goal"));
        setLinked(await fetchLinkedArtifacts(repoKey, nextMilestone));
        await loadWorkspace(nextMilestone.id);
      }
      setNotice(success);
      window.dispatchEvent(new CustomEvent("symphonia:specWorkspaceChanged", { detail: { repoKey } }));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Clarise could not update the milestone");
    } finally {
      setPending(null);
    }
  };

  const startMilestone = () =>
    runAction(
      "start",
      () => postLoop(repoKey, "start", {}),
      "Milestone draft created.",
    );

  const saveDiscussion = () => {
    if (!milestone) return;
    void runAction(
      "discuss",
      () =>
        postLoop(repoKey, `${milestone.id}/discuss`, {
          title,
          goal,
          answers,
        }),
      "Discussion saved.",
    );
  };

  const generateRequirements = () => {
    if (!milestone) return;
    void runAction(
      "requirements",
      () => postLoop(repoKey, `${milestone.id}/requirements`, {}),
      "Requirements generated.",
    );
  };

  const generatePlan = () => {
    if (!milestone) return;
    void runAction(
      "plan",
      () => postLoop(repoKey, `${milestone.id}/plan`, {}),
      "Plan generated.",
    );
  };

  const approveMilestone = () => {
    if (!milestone) return;
    void runAction(
      "approve",
      () => postLoop(repoKey, `${milestone.id}/approve`, {}),
      "Milestone approved.",
    );
  };

  const recordDecision = () => {
    if (!milestone || !decisionTitle.trim()) return;
    void runAction(
      "decision",
      () =>
        postLoop(repoKey, `${milestone.id}/decisions`, {
          title: decisionTitle.trim(),
          body: decisionBody.trim(),
        }),
      "Decision recorded.",
    ).then(() => {
      setDecisionTitle("");
      setDecisionBody("");
    });
  };

  const runTaskCompiler = async (
    key: string,
    action: () => Promise<TaskProposalPayload>,
    success: string,
  ) => {
    setPending(key);
    setError(null);
    setNotice(null);
    try {
      const payload = await action();
      setTaskProposal(payload);
      setNotice(success);
      window.dispatchEvent(new CustomEvent("symphonia:specWorkspaceChanged", { detail: { repoKey } }));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Clarise could not generate tasks");
    } finally {
      setPending(null);
    }
  };

  const generateTaskProposal = (regenerate = false) => {
    if (!milestone) return;
    void runTaskCompiler(
      "task-propose",
      () => postTaskCompiler(repoKey, milestone.id, "propose", { regenerate }),
      "Task proposal generated.",
    );
  };

  const createTasksFromProposal = (createPayload: TaskProposalCreatePayload) => {
    if (!milestone) return;
    void (async () => {
      setPending("task-create");
      setError(null);
      setNotice(null);
      try {
        const payload = await postTaskCompiler(repoKey, milestone.id, "create", createPayload);
        setTaskProposal(payload);
        window.dispatchEvent(
          new CustomEvent("symphonia:specWorkspaceChanged", { detail: { repoKey } }),
        );

        const createdTasks =
          payload.createdTasks ??
          payload.taskBoard?.createdTasks ??
          metadataList(payload.proposal, "created_tasks");

        if (payload.nextStep === "resolve_dependencies" && (payload.createdCount ?? 0) === 0) {
          setNotice("Resolve proposal dependencies before creating tasks.");
          return;
        }

        if (createdTasks.length > 0) {
          router.push(taskBoardHref(repoSlug, milestone.id, createdTasks));
        } else {
          setNotice("No new tasks were created.");
        }
      } catch (err) {
        setError(err instanceof Error ? err.message : "Clarise could not create tasks");
      } finally {
        setPending(null);
      }
    })();
  };

  if (loading) {
    return (
      <div className="grid min-h-full place-items-center px-6 py-12 text-sm text-muted-foreground">
        Loading planning...
      </div>
    );
  }

  return (
    <div className="min-h-full bg-background">
      <header className="border-b">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-3 px-4 py-4 sm:px-6">
          <div className="min-w-0 flex-1">
            <p className="text-xs font-medium uppercase text-muted-foreground">Planning</p>
            <h1 className="mt-1 text-2xl font-semibold tracking-normal">Planning handoff</h1>
            <p className="mt-1 max-w-2xl text-sm text-muted-foreground">
              Turn a milestone idea into reviewed, repo-backed tasks before any agent starts work.
            </p>
          </div>
          <button
            onClick={() => void startMilestone()}
            disabled={Boolean(pending)}
            className="inline-flex items-center gap-2 rounded-md border bg-foreground px-3 py-2 text-sm font-medium text-background hover:bg-foreground/90 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <Plus className="h-4 w-4" />
            {pending === "start" ? "Starting..." : "Start new milestone"}
          </button>
        </div>
      </header>

      <main className="mx-auto grid max-w-6xl gap-6 px-4 py-6 sm:px-6 lg:grid-cols-[16rem_minmax(0,1fr)]">
        <WorkflowRail milestone={milestone} linked={linked} proposal={taskProposal} />

        <div className="min-w-0 space-y-5">
          {error && <Notice tone="warn">{error}</Notice>}
          {notice && !error && <Notice tone="ok">{notice}</Notice>}

          {!milestone ? (
            <EmptyMilestoneState pending={pending === "start"} onStart={() => void startMilestone()} />
          ) : (
            <>
              {milestones.length > 1 && (
                <label className="flex max-w-sm items-center gap-2 text-xs text-muted-foreground">
                  Milestone
                  <select
                    value={selectedMilestoneId ?? milestone.id}
                    onChange={(event) => void loadWorkspace(event.target.value)}
                    className="min-w-0 flex-1 rounded-md border bg-background px-2 py-1 text-xs text-foreground"
                  >
                    {milestones.map((item) => (
                      <option key={item.id} value={item.id}>
                        {item.id} - {item.title}
                      </option>
                    ))}
                  </select>
                </label>
              )}

              <MilestoneHeader milestone={milestone} repoSlug={repoSlug} />

              <section className="border-y py-5">
                <div className="grid gap-4 md:grid-cols-[minmax(0,1fr)_minmax(16rem,22rem)]">
                  <div className="space-y-3">
                    <label className="block text-xs font-medium text-muted-foreground">
                      Milestone title
                      <input
                        value={title}
                        onChange={(event) => setTitle(event.target.value)}
                        className="mt-1 w-full rounded-md border bg-background px-3 py-2 text-sm text-foreground outline-none focus:ring-2 focus:ring-ring"
                      />
                    </label>
                    <label className="block text-xs font-medium text-muted-foreground">
                      Goal
                      <textarea
                        value={goal}
                        onChange={(event) => setGoal(event.target.value)}
                        rows={5}
                        className="mt-1 w-full resize-y rounded-md border bg-background px-3 py-2 text-sm leading-6 text-foreground outline-none focus:ring-2 focus:ring-ring"
                      />
                    </label>
                  </div>
                  <div className="rounded-md border bg-muted/20 p-3">
                    <p className="text-sm font-medium">Clarise will shape this into durable files.</p>
                    <p className="mt-2 text-sm leading-6 text-muted-foreground">
                      The source of truth stays in this repository, so the team can
                      inspect the milestone, requirements, plan, and task proposal before work begins.
                    </p>
                    <dl className="mt-4 space-y-2 text-xs">
                      <MetaLine label="Discussion" value={metadataString(milestone, "discussion")} />
                      <MetaLine label="Requirements" value={metadataString(milestone, "requirements")} />
                      <MetaLine label="Plan" value={metadataString(milestone, "plan")} />
                    </dl>
                  </div>
                </div>
              </section>

              {milestone.status !== "approved" && (
                <DiscussionForm
                  questions={questions}
                  answers={answers}
                  pending={pending === "discuss"}
                  onAnswer={(id, value) => setAnswers((current) => ({ ...current, [id]: value }))}
                  onSave={saveDiscussion}
                />
              )}

              <ArtifactProgress
                repoSlug={repoSlug}
                milestone={milestone}
                linked={linked}
                pending={pending}
                onRequirements={generateRequirements}
                onPlan={generatePlan}
                onApprove={approveMilestone}
              />

              {(milestone.status === "plan_ready" ||
                milestone.status === "ready_for_approval" ||
                milestone.status === "approved") && (
                <DecisionPanel
                  repoSlug={repoSlug}
                  milestone={milestone}
                  title={decisionTitle}
                  body={decisionBody}
                  pending={pending === "decision"}
                  onTitle={setDecisionTitle}
                  onBody={setDecisionBody}
                  onRecord={recordDecision}
                />
              )}

              {milestone.status === "approved" && (
                <section className="border-t py-5">
                  <div className="flex items-start gap-3">
                    <CheckCircle2 className="mt-0.5 h-5 w-5 text-emerald-500" />
                    <div>
                      <h2 className="text-base font-semibold">Plan approved</h2>
                      <p className="mt-1 text-sm leading-6 text-muted-foreground">
                        Clarise can now turn this plan into implementation tasks. Creating tasks
                        only creates To-do tasks; assigning work remains a separate action.
                      </p>
                    </div>
                  </div>
                </section>
              )}

              {milestone.status === "approved" && (
                <TaskProposalPanel
                  repoSlug={repoSlug}
                  proposal={taskProposal}
                  pending={pending}
                  onGenerate={() => generateTaskProposal(false)}
                  onRegenerate={() => generateTaskProposal(true)}
                  onCreate={createTasksFromProposal}
                  onCancel={() => setTaskProposal(null)}
                />
              )}
            </>
          )}
        </div>
      </main>
    </div>
  );
}

function WorkflowRail({
  milestone,
  linked,
  proposal,
}: {
  milestone: SpecArtifact | null;
  linked: LinkedArtifacts;
  proposal: TaskProposalPayload | null;
}) {
  const activeIndex = workflowIndex(milestone, linked, proposal);

  return (
    <aside className="border-b pb-4 lg:border-b-0 lg:border-r lg:pr-4">
      <ol className="grid gap-2 sm:grid-cols-6 lg:grid-cols-1">
        {STEPS.map((step, index) => {
          const Icon = step.icon;
          const done = index < activeIndex;
          const active = index === activeIndex;

          return (
            <li
              key={step.key}
              className={cn(
                "flex items-center gap-2 rounded-md px-2 py-2 text-sm",
                active && "bg-muted text-foreground",
                !active && "text-muted-foreground",
              )}
            >
              <span
                className={cn(
                  "grid h-7 w-7 shrink-0 place-items-center rounded-md border",
                  done && "border-emerald-500/30 bg-emerald-500/10 text-emerald-600",
                  active && "border-foreground/20 bg-background text-foreground",
                )}
              >
                {done ? <CheckCircle2 className="h-4 w-4" /> : <Icon className="h-4 w-4" />}
              </span>
              <span className="truncate">{step.label}</span>
            </li>
          );
        })}
      </ol>
    </aside>
  );
}

function EmptyMilestoneState({
  pending,
  onStart,
}: {
  pending: boolean;
  onStart: () => void;
}) {
  return (
    <section className="grid min-h-[28rem] place-items-center border-y py-12 text-center">
      <div className="max-w-md">
        <span className="mx-auto grid h-11 w-11 place-items-center rounded-md bg-muted text-emerald-600">
          <Milestone className="h-5 w-5" />
        </span>
        <h2 className="mt-4 text-xl font-semibold">Start a planning handoff with Clarise</h2>
        <p className="mt-2 text-sm leading-6 text-muted-foreground">
          Clarise will help turn a rough milestone idea into requirements, a plan, a reviewed
          task proposal, and To-do tasks on the board.
        </p>
        <button
          onClick={onStart}
          disabled={pending}
          className="mt-5 inline-flex items-center gap-2 rounded-md border bg-foreground px-3 py-2 text-sm font-medium text-background hover:bg-foreground/90 disabled:cursor-not-allowed disabled:opacity-50"
        >
          <Plus className="h-4 w-4" />
          {pending ? "Starting..." : "Start new milestone"}
        </button>
      </div>
    </section>
  );
}

function MilestoneHeader({ milestone, repoSlug }: { milestone: SpecArtifact; repoSlug: string }) {
  return (
    <section className="flex flex-wrap items-start gap-3">
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
          <span className="rounded-full border px-2 py-0.5">{milestone.id}</span>
          <span className="rounded-full border px-2 py-0.5">{STATUS_LABELS[milestone.status]}</span>
        </div>
        <h2 className="mt-2 text-2xl font-semibold tracking-normal">{milestone.title}</h2>
      </div>
      <Link
        href={`/r/${repoSlug}/workspace/milestone/${encodeURIComponent(milestone.id)}`}
        className="inline-flex items-center gap-2 rounded-md border px-3 py-2 text-sm hover:bg-muted"
      >
        <PenLine className="h-4 w-4" />
        Edit proposal
      </Link>
    </section>
  );
}

function DiscussionForm({
  questions,
  answers,
  pending,
  onAnswer,
  onSave,
}: {
  questions: Question[];
  answers: Record<string, string>;
  pending: boolean;
  onAnswer: (id: string, value: string) => void;
  onSave: () => void;
}) {
  return (
    <section className="border-y py-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-base font-semibold">Discuss milestone</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Answer what matters now. Clarise saves the discussion in this repository.
          </p>
        </div>
        <button
          onClick={onSave}
          disabled={pending}
          className="inline-flex items-center gap-2 rounded-md border bg-background px-3 py-2 text-sm hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
        >
          <MessageSquareText className="h-4 w-4" />
          {pending ? "Saving..." : "Save discussion"}
        </button>
      </div>
      <div className="mt-4 divide-y rounded-md border">
        {questions.map((question) => (
          <label key={question.id} className="block p-3">
            <span className="text-sm font-medium">{question.question}</span>
            <textarea
              value={answers[question.id] ?? ""}
              onChange={(event) => onAnswer(question.id, event.target.value)}
              rows={3}
              className="mt-2 w-full resize-y rounded-md border bg-background px-3 py-2 text-sm leading-6 outline-none focus:ring-2 focus:ring-ring"
            />
          </label>
        ))}
      </div>
    </section>
  );
}

function ArtifactProgress({
  repoSlug,
  milestone,
  linked,
  pending,
  onRequirements,
  onPlan,
  onApprove,
}: {
  repoSlug: string;
  milestone: SpecArtifact;
  linked: LinkedArtifacts;
  pending: string | null;
  onRequirements: () => void;
  onPlan: () => void;
  onApprove: () => void;
}) {
  const canGenerateRequirements = milestone.status === "in_discussion" || Boolean(linked.discussion);
  const canGeneratePlan = milestone.status === "requirements_ready" || Boolean(linked.requirements);
  const canApprove =
    milestone.status === "plan_ready" ||
    milestone.status === "ready_for_approval" ||
    Boolean(linked.plan);

  return (
    <section className="border-y py-5">
      <h2 className="text-base font-semibold">Planning artifacts</h2>
      <div className="mt-4 grid gap-4 lg:grid-cols-3">
        <ArtifactPane
          title="Discussion"
          artifact={linked.discussion}
          repoSlug={repoSlug}
          fallback="Save the guided discussion to create this file."
        />
        <ArtifactPane
          title="Requirements"
          artifact={linked.requirements}
          repoSlug={repoSlug}
          fallback="Generate requirements after the discussion is saved."
        />
        <ArtifactPane
          title="Plan"
          artifact={linked.plan}
          repoSlug={repoSlug}
          fallback="Generate a plan after requirements are ready."
        />
      </div>
      {milestone.status !== "approved" && (
        <div className="mt-4 flex flex-wrap gap-2">
          <button
            onClick={onRequirements}
            disabled={!canGenerateRequirements || Boolean(pending)}
            className="inline-flex items-center gap-2 rounded-md border px-3 py-2 text-sm hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
          >
            <ListChecks className="h-4 w-4" />
            {pending === "requirements" ? "Generating..." : "Generate requirements"}
          </button>
          <button
            onClick={onPlan}
            disabled={!canGeneratePlan || Boolean(pending)}
            className="inline-flex items-center gap-2 rounded-md border px-3 py-2 text-sm hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
          >
            <FileText className="h-4 w-4" />
            {pending === "plan" ? "Generating..." : "Generate plan"}
          </button>
          <button
            onClick={onApprove}
            disabled={!canApprove || Boolean(pending)}
            className="inline-flex items-center gap-2 rounded-md border bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <ShieldCheck className="h-4 w-4" />
            {pending === "approve" ? "Approving..." : "Approve milestone"}
          </button>
        </div>
      )}
    </section>
  );
}

function ArtifactPane({
  title,
  artifact,
  repoSlug,
  fallback,
}: {
  title: string;
  artifact?: SpecArtifact | null;
  repoSlug: string;
  fallback: string;
}) {
  return (
    <article className="min-h-52 rounded-md border bg-background">
      <div className="flex items-center justify-between gap-2 border-b px-3 py-2">
        <h3 className="text-sm font-semibold">{title}</h3>
        {artifact ? (
          <Link
            href={`/r/${repoSlug}/workspace/${encodeURIComponent(artifact.type)}/${encodeURIComponent(
              artifact.id,
            )}`}
            className="text-xs text-muted-foreground hover:text-foreground"
          >
            Open
          </Link>
        ) : (
          <Circle className="h-3.5 w-3.5 text-muted-foreground" />
        )}
      </div>
      <div className="px-3 py-3">
        {artifact ? (
          <>
            <p className="truncate text-sm font-medium">{artifact.title}</p>
            <p className="mt-1 text-xs text-muted-foreground">{artifact.id}</p>
            <p className="mt-3 line-clamp-6 whitespace-pre-line text-sm leading-6 text-muted-foreground">
              {previewBody(artifact.body)}
            </p>
          </>
        ) : (
          <p className="text-sm leading-6 text-muted-foreground">{fallback}</p>
        )}
      </div>
    </article>
  );
}

function DecisionPanel({
  repoSlug,
  milestone,
  title,
  body,
  pending,
  onTitle,
  onBody,
  onRecord,
}: {
  repoSlug: string;
  milestone: SpecArtifact;
  title: string;
  body: string;
  pending: boolean;
  onTitle: (value: string) => void;
  onBody: (value: string) => void;
  onRecord: () => void;
}) {
  const decisionIds = Array.isArray(milestone.metadata.decisions) ? milestone.metadata.decisions : [];

  return (
    <section className="border-y py-5">
      <div className="flex flex-wrap items-start gap-4">
        <div className="min-w-0 flex-1">
          <h2 className="text-base font-semibold">Decisions</h2>
          <p className="mt-1 text-sm leading-6 text-muted-foreground">
            Record decisions that should travel with this milestone.
          </p>
          {decisionIds.length > 0 && (
            <div className="mt-3 flex flex-wrap gap-2">
              {decisionIds.map((id) => (
                <Link
                  key={id}
                  href={`/r/${repoSlug}/workspace/decision/${encodeURIComponent(id)}`}
                  className="rounded-full border px-2 py-1 text-xs hover:bg-muted"
                >
                  {id}
                </Link>
              ))}
            </div>
          )}
        </div>
        <div className="w-full max-w-md space-y-2">
          <input
            value={title}
            onChange={(event) => onTitle(event.target.value)}
            placeholder="Decision title"
            className="w-full rounded-md border bg-background px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-ring"
          />
          <textarea
            value={body}
            onChange={(event) => onBody(event.target.value)}
            placeholder="Decision notes"
            rows={4}
            className="w-full resize-y rounded-md border bg-background px-3 py-2 text-sm leading-6 outline-none focus:ring-2 focus:ring-ring"
          />
          <button
            onClick={onRecord}
            disabled={!title.trim() || pending}
            className="inline-flex items-center gap-2 rounded-md border px-3 py-2 text-sm hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
          >
            <Plus className="h-4 w-4" />
            {pending ? "Recording..." : "Record decision"}
          </button>
        </div>
      </div>
    </section>
  );
}

function TaskProposalPanel({
  repoSlug,
  proposal,
  pending,
  onGenerate,
  onRegenerate,
  onCreate,
  onCancel,
}: {
  repoSlug: string;
  proposal: TaskProposalPayload | null;
  pending: string | null;
  onGenerate: () => void;
  onRegenerate: () => void;
  onCreate: (payload: TaskProposalCreatePayload) => void;
  onCancel: () => void;
}) {
  const items = proposal?.items ?? [];
  const [draftItems, setDraftItems] = useState<TaskProposalItem[]>([]);
  const createdTasks = proposal?.createdTasks ?? metadataList(proposal?.proposal, "created_tasks");
  const hasCreatedTasks = createdTasks.length > 0;
  const isPending = pending === "task-propose" || pending === "task-create";
  const selectedCount = draftItems.filter((item) => item.selected !== false).length;
  const readiness = proposal?.automationReadiness ?? readinessFromItems(draftItems);

  useEffect(() => {
    setDraftItems(items.map(normalizeProposalItem));
  }, [items, proposal?.generationId]);

  const updateItem = (id: string, patch: Partial<TaskProposalItem>) => {
    setDraftItems((current) =>
      current.map((item) => (item.id === id ? normalizeProposalItem({ ...item, ...patch }) : item)),
    );
  };

  const moveItem = (id: string, direction: -1 | 1) => {
    setDraftItems((current) => {
      const index = current.findIndex((item) => item.id === id);
      const nextIndex = index + direction;
      if (index < 0 || nextIndex < 0 || nextIndex >= current.length) return current;
      const next = [...current];
      const [item] = next.splice(index, 1);
      next.splice(nextIndex, 0, item);
      return next;
    });
  };

  const createPayload = (sourceItems: TaskProposalItem[]): TaskProposalCreatePayload => ({
    selectedProposalItemIds: sourceItems
      .filter((item) => item.selected !== false)
      .map((item) => item.id),
    items: sourceItems.map(normalizeProposalItem),
  });

  const createAllPayload = (): TaskProposalCreatePayload =>
    createPayload(draftItems.map((item) => ({ ...item, selected: true })));

  return (
    <section className="border-y py-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <h2 className="text-base font-semibold">Task proposal</h2>
          <p className="mt-1 max-w-2xl text-sm leading-6 text-muted-foreground">
            Review the proposed task breakdown before Symphonia writes any task files.
          </p>
        </div>
        {proposal?.proposal && (
          <Link
            href={`/r/${repoSlug}/workspace/task_proposal/${encodeURIComponent(proposal.proposal.id)}`}
            className="inline-flex items-center gap-2 rounded-md border px-3 py-2 text-sm hover:bg-muted"
          >
            <ExternalLink className="h-4 w-4" />
            Open proposal
          </Link>
        )}
      </div>

      {!proposal && (
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-md border bg-muted/20 px-3 py-3">
          <div>
            <p className="text-sm font-medium">Milestone approved</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Clarise can now turn this plan into board-ready tasks.
            </p>
          </div>
          <button
            onClick={onGenerate}
            disabled={isPending}
            className="inline-flex items-center gap-2 rounded-md border bg-foreground px-3 py-2 text-sm font-medium text-background hover:bg-foreground/90 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <ClipboardList className="h-4 w-4" />
            {pending === "task-propose" ? "Compiling..." : "Compile tasks"}
          </button>
        </div>
      )}

      {proposal && items.length === 0 && !hasCreatedTasks && (
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-md border bg-muted/20 px-3 py-3">
          <div>
            <p className="text-sm font-medium">Saved proposal found</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Open the proposal, or regenerate the review list here.
            </p>
          </div>
          <button
            onClick={onGenerate}
            disabled={isPending}
            className="inline-flex items-center gap-2 rounded-md border px-3 py-2 text-sm hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
          >
            <ClipboardList className="h-4 w-4" />
            {pending === "task-propose" ? "Compiling..." : "Compile tasks"}
          </button>
        </div>
      )}

      {items.length > 0 && !hasCreatedTasks && (
        <div className="mt-4 space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <p className="text-sm font-medium">Clarise proposed {items.length} tasks.</p>
              <p className="mt-1 text-xs text-muted-foreground">
                {selectedCount} selected. Edit the proposal before writing task files.
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <button
                onClick={() => onCreate(createPayload(draftItems))}
                disabled={isPending || selectedCount === 0}
                className="inline-flex items-center gap-2 rounded-md border bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
              >
                <CheckCircle2 className="h-4 w-4" />
                {pending === "task-create" ? "Creating..." : "Create selected"}
              </button>
              <button
                onClick={() => onCreate(createAllPayload())}
                disabled={isPending}
                className="inline-flex items-center gap-2 rounded-md border px-3 py-2 text-sm hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
              >
                <ClipboardList className="h-4 w-4" />
                Create all
              </button>
              <button
                onClick={onRegenerate}
                disabled={isPending}
                className="inline-flex items-center gap-2 rounded-md border px-3 py-2 text-sm hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
              >
                <RefreshCcw className="h-4 w-4" />
                Regenerate
              </button>
              <button
                onClick={onCancel}
                disabled={isPending}
                className="inline-flex items-center gap-2 rounded-md border px-3 py-2 text-sm hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
              >
                <X className="h-4 w-4" />
                Cancel
              </button>
            </div>
          </div>
          <HarnessReadinessPanel readiness={readiness} />
          {(proposal?.blockers?.length ?? 0) > 0 && proposal?.nextStep === "resolve_dependencies" && (
            <Notice tone="warn">
              Resolve proposal dependencies before creating tasks. Dependencies must be selected or already created.
            </Notice>
          )}
          <div className="divide-y rounded-md border">
            {draftItems.map((item, index) => (
              <TaskProposalItemRow
                key={item.id}
                item={item}
                index={index}
                total={draftItems.length}
                disabled={isPending}
                onChange={(patch) => updateItem(item.id, patch)}
                onMove={(direction) => moveItem(item.id, direction)}
              />
            ))}
          </div>
        </div>
      )}

      {hasCreatedTasks && (
        <div className="mt-4 rounded-md border px-3 py-3">
          <div className="flex items-start gap-3">
            <CheckCircle2 className="mt-0.5 h-5 w-5 text-emerald-500" />
            <div>
              <p className="text-sm font-medium">Tasks created</p>
              <p className="mt-1 text-sm leading-6 text-muted-foreground">
                These tasks are on the task board as To-do. Assigning a task to the Coding
                Assistant remains a separate action.
              </p>
              <div className="mt-3 flex flex-wrap gap-2">
                <Link
                  href={taskBoardHref(
                    repoSlug,
                    metadataString(proposal?.proposal, "source_milestone"),
                    createdTasks,
                  )}
                  className="inline-flex items-center gap-2 rounded-md border bg-foreground px-3 py-1.5 text-xs font-medium text-background hover:bg-foreground/90"
                >
                  Review task board
                  <ArrowRight className="h-3.5 w-3.5" />
                </Link>
                {createdTasks.map((key) => (
                  <Link
                    key={key}
                    href={`/r/${repoSlug}/tasks/${encodeURIComponent(key)}`}
                    className="rounded-full border px-2 py-1 text-xs hover:bg-muted"
                  >
                    {key}
                  </Link>
                ))}
              </div>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}

function HarnessReadinessPanel({ readiness }: { readiness: AutomationReadiness }) {
  const hasWarnings = readiness.warnings.length > 0;
  const hasBlockers = readiness.blockers.length > 0;

  return (
    <div className="rounded-md border bg-muted/20 px-3 py-3">
      <div className="flex flex-wrap items-center gap-2">
        {readiness.ready ? (
          <CheckCircle2 className="h-4 w-4 text-emerald-500" />
        ) : (
          <AlertTriangle className="h-4 w-4 text-amber-500" />
        )}
        <p className="text-sm font-medium">Harness readiness</p>
        <span className="rounded-full border px-2 py-0.5 text-xs text-muted-foreground">
          {readiness.ready ? "Ready estimate" : "Advisory blockers"}
        </span>
      </div>
      <p className="mt-2 text-sm leading-6 text-muted-foreground">
        This preview estimates obvious setup issues. Harness eligibility remains authoritative after task creation.
      </p>
      {(hasBlockers || hasWarnings) && (
        <div className="mt-3 grid gap-3 text-sm md:grid-cols-2">
          <ReadinessList title="Blocked" items={readiness.blockers} fallback="No obvious blockers." />
          <ReadinessList title="Warnings" items={readiness.warnings} fallback="No warnings." />
        </div>
      )}
    </div>
  );
}

function ReadinessList({
  title,
  items,
  fallback,
}: {
  title: string;
  items: string[];
  fallback: string;
}) {
  return (
    <div>
      <p className="text-xs font-medium text-muted-foreground">{title}</p>
      {items.length > 0 ? (
        <ul className="mt-1 space-y-1 text-xs text-muted-foreground">
          {items.map((item) => (
            <li key={item}>{item}</li>
          ))}
        </ul>
      ) : (
        <p className="mt-1 text-xs text-muted-foreground">{fallback}</p>
      )}
    </div>
  );
}

function TaskProposalItemRow({
  item,
  index,
  total,
  disabled,
  onChange,
  onMove,
}: {
  item: TaskProposalItem;
  index: number;
  total: number;
  disabled: boolean;
  onChange: (patch: Partial<TaskProposalItem>) => void;
  onMove: (direction: -1 | 1) => void;
}) {
  return (
    <article className="grid gap-3 p-3 md:grid-cols-[2.75rem_minmax(0,1fr)_minmax(13rem,18rem)]">
      <div className="space-y-2">
        <label
          className={cn(
            "grid h-8 w-8 place-items-center rounded-md border text-xs font-medium",
            item.selected === false
              ? "bg-background text-muted-foreground"
              : "border-emerald-500/30 bg-emerald-500/10 text-emerald-700",
          )}
        >
          <input
            type="checkbox"
            checked={item.selected !== false}
            disabled={disabled}
            onChange={(event) => onChange({ selected: event.target.checked })}
            className="sr-only"
          />
          {index + 1}
        </label>
        <div className="grid gap-1">
          <button
            type="button"
            disabled={disabled || index === 0}
            onClick={() => onMove(-1)}
            className="grid h-7 w-8 place-items-center rounded-md border text-muted-foreground hover:bg-muted disabled:cursor-not-allowed disabled:opacity-40"
            aria-label="Move task up"
          >
            <ArrowUp className="h-3.5 w-3.5" />
          </button>
          <button
            type="button"
            disabled={disabled || index === total - 1}
            onClick={() => onMove(1)}
            className="grid h-7 w-8 place-items-center rounded-md border text-muted-foreground hover:bg-muted disabled:cursor-not-allowed disabled:opacity-40"
            aria-label="Move task down"
          >
            <ArrowDown className="h-3.5 w-3.5" />
          </button>
        </div>
      </div>
      <div className="min-w-0">
        <label className="block text-xs font-medium text-muted-foreground">
          Title
          <input
            value={item.title}
            disabled={disabled}
            onChange={(event) => onChange({ title: event.target.value })}
            className="mt-1 w-full rounded-md border bg-background px-3 py-2 text-sm font-medium text-foreground outline-none focus:ring-2 focus:ring-ring disabled:opacity-60"
          />
        </label>
        <p className="mt-1 text-xs text-muted-foreground">{item.id}</p>
        <p className="mt-2 text-sm leading-6 text-muted-foreground">{item.goal}</p>
        <label className="mt-3 block text-xs font-medium text-muted-foreground">
          Acceptance criteria
          <textarea
            value={item.acceptance_criteria.join("\n")}
            disabled={disabled}
            rows={3}
            onChange={(event) =>
              onChange({ acceptance_criteria: splitLines(event.target.value) })
            }
            className="mt-1 w-full resize-y rounded-md border bg-background px-3 py-2 text-sm leading-6 text-foreground outline-none focus:ring-2 focus:ring-ring disabled:opacity-60"
          />
        </label>
        <label className="mt-3 block text-xs font-medium text-muted-foreground">
          Review expectations
          <textarea
            value={item.review_expectations.join("\n")}
            disabled={disabled}
            rows={3}
            onChange={(event) =>
              onChange({ review_expectations: splitLines(event.target.value) })
            }
            className="mt-1 w-full resize-y rounded-md border bg-background px-3 py-2 text-sm leading-6 text-foreground outline-none focus:ring-2 focus:ring-ring disabled:opacity-60"
          />
        </label>
      </div>
      <div className="space-y-2 text-xs text-muted-foreground">
        <label className="block text-xs font-medium text-muted-foreground">
          Priority
          <select
            value={item.priority}
            disabled={disabled}
            onChange={(event) => onChange({ priority: event.target.value })}
            className="mt-1 w-full rounded-md border bg-background px-2 py-2 text-xs text-foreground disabled:opacity-60"
          >
            {["urgent", "high", "medium", "low", "no-priority"].map((priority) => (
              <option key={priority} value={priority}>
                {priority}
              </option>
            ))}
          </select>
        </label>
        <label className="block text-xs font-medium text-muted-foreground">
          Depends on
          <textarea
            value={item.depends_on.join("\n")}
            disabled={disabled}
            rows={3}
            onChange={(event) => onChange({ depends_on: splitLines(event.target.value) })}
            className="mt-1 w-full resize-y rounded-md border bg-background px-2 py-2 font-mono text-[11px] text-foreground outline-none focus:ring-2 focus:ring-ring disabled:opacity-60"
          />
        </label>
        <MetaLine label="Selected" value={item.selected === false ? "No" : "Yes"} />
      </div>
    </article>
  );
}

function MetaLine({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="truncate font-mono text-[11px]">{value}</dd>
    </div>
  );
}

function Notice({ tone, children }: { tone: "ok" | "warn"; children: ReactNode }) {
  return (
    <div
      className={cn(
        "rounded-md border px-3 py-2 text-sm",
        tone === "ok"
          ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300"
          : "border-amber-500/30 bg-amber-500/10 text-amber-700 dark:text-amber-300",
      )}
    >
      {children}
    </div>
  );
}

async function fetchWorkspace(repoKey: string): Promise<SpecWorkspacePayload> {
  const res = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/spec-workspace`, {
    cache: "no-store",
  });
  const payload = (await res.json()) as { specWorkspace?: SpecWorkspacePayload; error?: string };
  if (!res.ok || !payload.specWorkspace) {
    throw new Error(payload.error ?? "Could not load workspace");
  }
  return payload.specWorkspace;
}

async function fetchArtifact(repoKey: string, type: string, id: string): Promise<SpecArtifact> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/spec-workspace/artifacts/${encodeURIComponent(
      type,
    )}/${encodeURIComponent(id)}`,
    { cache: "no-store" },
  );
  const payload = (await res.json()) as { artifact?: SpecArtifact; error?: string };
  if (!res.ok || !payload.artifact) {
    throw new Error(payload.error ?? "Could not load planning document");
  }
  return payload.artifact;
}

async function fetchLinkedArtifacts(repoKey: string, milestone: SpecArtifact): Promise<LinkedArtifacts> {
  const entries = await Promise.all(
    (["discussion", "requirements", "plan"] as const).map(async (type) => {
      const id = metadataString(milestone, type);
      if (!id) return [type, null] as const;
      try {
        return [type, await fetchArtifact(repoKey, type, id)] as const;
      } catch {
        return [type, null] as const;
      }
    }),
  );
  return Object.fromEntries(entries) as LinkedArtifacts;
}

async function fetchExistingTaskProposal(
  repoKey: string,
  milestoneId: string,
): Promise<TaskProposalPayload | null> {
  try {
    const proposal = await fetchArtifact(repoKey, "task_proposal", `${milestoneId}-task-proposal`);
    return {
      proposal,
      items: metadataProposalItems(proposal),
      createdTasks: metadataList(proposal, "created_tasks"),
      generationId: metadataString(proposal, "generation_id"),
      blockers: metadataList(proposal, "blockers"),
      warnings: metadataList(proposal, "warnings"),
      automationReadiness: {
        ready: metadataList(proposal, "blockers").length === 0,
        blockers: metadataList(proposal, "blockers"),
        warnings: metadataList(proposal, "warnings"),
      },
    };
  } catch {
    return null;
  }
}

async function postLoop(repoKey: string, path: string, body: unknown): Promise<LoopPayload> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/clarise/milestones/${path}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    },
  );
  const payload = (await res.json()) as LoopPayload;
  if (!res.ok) throw new Error(payload.error ?? "Clarise could not update the milestone");
  return payload;
}

async function postTaskCompiler(
  repoKey: string,
  milestoneId: string,
  action: "propose" | "create",
  body: unknown,
): Promise<TaskProposalPayload> {
  const res = await fetch(
    `/api/repositories/${encodeURIComponent(repoKey)}/clarise/milestones/${encodeURIComponent(
      milestoneId,
    )}/tasks/${action}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    },
  );
  const payload = (await res.json()) as TaskProposalPayload;
  if (!res.ok) throw new Error(payload.error ?? "Clarise could not generate tasks");
  return payload;
}

function milestoneSummaries(workspace: SpecWorkspacePayload | null): SpecArtifactSummary[] {
  if (!workspace?.state.initialized) return [];
  return workspace.sections
    .flatMap((section) => section.artifacts)
    .filter((artifact) => artifact.type === "milestone")
    .sort((a, b) => a.id.localeCompare(b.id));
}

function workflowIndex(
  milestone: SpecArtifact | null,
  linked: LinkedArtifacts,
  proposal: TaskProposalPayload | null,
): number {
  if (!milestone) return 0;
  const createdTasks = proposal?.createdTasks ?? metadataList(proposal?.proposal, "created_tasks");
  if (createdTasks.length > 0) return STEPS.length;
  if (milestone.status === "approved") return 5;
  if (milestone.status === "plan_ready" || milestone.status === "ready_for_approval" || linked.plan) {
    return 4;
  }
  if (milestone.status === "requirements_ready" || linked.requirements) return 3;
  if (milestone.status === "in_discussion" || linked.discussion) return 2;
  return 1;
}

function normalizeProposalItem(item: TaskProposalItem): TaskProposalItem {
  return {
    ...item,
    selected: item.selected !== false,
    priority: item.priority || "medium",
    depends_on: normalizeStringList(item.depends_on),
    implementation_notes: normalizeStringList(item.implementation_notes),
    acceptance_criteria: normalizeStringList(item.acceptance_criteria),
    review_expectations: normalizeStringList(item.review_expectations),
    related_artifacts: normalizeStringList(item.related_artifacts),
    linked_files: normalizeStringList(item.linked_files),
  };
}

function readinessFromItems(items: TaskProposalItem[]): AutomationReadiness {
  const readiness = items
    .map((item) => item.automation_readiness)
    .find((value): value is AutomationReadiness => Boolean(value));

  return readiness ?? { ready: true, blockers: [], warnings: [] };
}

function metadataProposalItems(artifact: SpecArtifact | undefined): TaskProposalItem[] {
  const value = artifact?.metadata.proposal_items;
  if (!Array.isArray(value)) return [];

  return value
    .filter((item): item is Record<string, unknown> => Boolean(item) && typeof item === "object")
    .map((item) =>
      normalizeProposalItem({
        id: stringValue(item.id),
        selected: item.selected !== false,
        title: stringValue(item.title),
        body: stringValue(item.body),
        priority: stringValue(item.priority) || "medium",
        depends_on: normalizeStringList(item.depends_on),
        goal: stringValue(item.goal),
        implementation_notes: normalizeStringList(item.implementation_notes),
        acceptance_criteria: normalizeStringList(item.acceptance_criteria),
        review_expectations: normalizeStringList(item.review_expectations),
        related_artifacts: normalizeStringList(item.related_artifacts),
        linked_files: normalizeStringList(item.linked_files),
        automation_readiness: readinessValue(item.automation_readiness),
      }),
    )
    .filter((item) => item.id && item.title);
}

function readinessValue(value: unknown): AutomationReadiness | undefined {
  if (!value || typeof value !== "object") return undefined;
  const raw = value as Record<string, unknown>;
  return {
    ready: raw.ready === true,
    blockers: normalizeStringList(raw.blockers),
    warnings: normalizeStringList(raw.warnings),
  };
}

function splitLines(value: string): string[] {
  return normalizeStringList(value.split("\n"));
}

function normalizeStringList(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return typeof value === "string" && value.trim() ? [value.trim()] : [];
  }

  return value
    .map((item) => (typeof item === "string" ? item.trim() : ""))
    .filter(Boolean);
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function metadataString(artifact: SpecArtifact | undefined, key: string): string {
  const value = artifact?.metadata[key];
  return typeof value === "string" ? value : "";
}

function metadataList(artifact: SpecArtifact | undefined, key: string): string[] {
  const value = artifact?.metadata[key];
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function sectionFromBody(body: string, heading: string): string {
  const escaped = heading.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = body.match(new RegExp(`^## ${escaped}\\s*\\n([\\s\\S]*?)(?=^## |$)`, "m"));
  return match?.[1]?.trim() ?? "";
}

function previewBody(body: string): string {
  return body
    .split("\n")
    .filter((line) => !line.startsWith("# "))
    .join("\n")
    .trim();
}

function taskBoardHref(repoSlug: string, sourceMilestone: string, createdTasks: string[]): string {
  const params = new URLSearchParams();
  if (sourceMilestone) params.set("sourceMilestone", sourceMilestone);
  if (createdTasks.length > 0) params.set("created", createdTasks.join(","));
  params.set("handoff", "1");
  return `/r/${repoSlug}/tasks?${params.toString()}`;
}
