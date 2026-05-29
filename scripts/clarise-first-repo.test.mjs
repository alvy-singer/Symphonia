import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import ts from "typescript";

const require = createRequire(import.meta.url);

async function source(path) {
  return readFile(new URL(`../${path}`, import.meta.url), "utf8");
}

async function loadTs(path, outName) {
  const input = await source(path);
  const compiled = ts.transpileModule(input, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
      importsNotUsedAsValues: ts.ImportsNotUsedAsValues.Remove,
    },
  });
  const tempDir = await mkdtemp(join(tmpdir(), "symphonia-clarise-first-"));
  const outputPath = join(tempDir, outName);
  await writeFile(outputPath, compiled.outputText);
  return require(outputPath);
}

test("repo opening lands on the Clarise repo home, not tasks or workspace", async () => {
  const repoPage = await source("app/r/[repoKey]/page.tsx");
  const dashboard = await source("app/dashboard/page.tsx");
  const sidebar = await source("components/sidebar/sidebar-body.tsx");
  const docTree = await source("components/sidebar/doc-tree.tsx");
  const palette = await source("components/command-palette.tsx");

  assert.match(repoPage, /ClariseRepoHome/);
  assert.doesNotMatch(repoPage, /redirect\(/);

  assert.match(dashboard, /router\.push\(`\/r\/\$\{openedRepository\.key\.toLowerCase\(\)\}`\)/);
  assert.match(dashboard, /const href = `\/r\/\$\{repository\.key\.toLowerCase\(\)\}`/);
  assert.doesNotMatch(dashboard, /openDashboardClarise/);
  assert.doesNotMatch(dashboard, /aria-label="Ask Clarise"/);
  assert.match(dashboard, /Clarise creates the workspace files/);
  assert.match(dashboard, /Use Clarise to create workspace files/);
  assert.doesNotMatch(dashboard, /openedRepository\.key\.toLowerCase\(\)\}\/tasks/);

  assert.match(sidebar, /label="Clarise"/);
  assert.match(sidebar, /href=\{`\/r\/\$\{t\.key\.toLowerCase\(\)\}`\}/);
  assert.match(sidebar, /<DocTree repoKey=\{repoKey\} \/>/);
  assert.doesNotMatch(sidebar, /Document tree menu/);
  assert.doesNotMatch(sidebar, /Open document tree/);
  assert.doesNotMatch(sidebar, /Close document tree/);
  assert.doesNotMatch(sidebar, /symphonia\.doctreeOpen/);
  assert.match(sidebar, /<WorkspaceCreateMenu pending=\{workspacePagePending\} onCreate=\{createWorkspacePage\} \/>/);
  assert.match(sidebar, /aria-label="Create workspace page"/);
  assert.match(sidebar, /<Plus className="h-3\.5 w-3\.5" \/>/);
  assert.doesNotMatch(docTree, /aria-label="Pages menu"/);
  assert.doesNotMatch(docTree, /aria-label="New page"/);
  assert.doesNotMatch(docTree, /aria-label="Open trash"/);
  assert.doesNotMatch(docTree, /tabular-nums[\s\S]*artifacts\.length/);

  assert.match(palette, /id: "nav-clarise"/);
  assert.match(palette, /id: "nav-workflow"/);
  assert.match(palette, /repositories\.forEach[\s\S]+id: "nav-workflow"[\s\S]+id: "nav-clarise"/);
  assert.match(palette, /router\.push\(`\/r\/\$\{slug\(r\.key\)\}`\)/);
  assert.doesNotMatch(palette, /id: "nav-tasks"/);
  assert.doesNotMatch(palette, /id: "nav-projects"/);
  assert.doesNotMatch(palette, /id: "nav-docs"/);
  assert.doesNotMatch(palette, /pages\.forEach/);
  assert.doesNotMatch(palette, /Search repositories, pages, or actions/);
});

test("Clarise home keeps chat private and exposes workspace result actions", async () => {
  const home = await source("components/clarise-repo-home.tsx");

  assert.match(home, /AssistantRuntimeProvider/);
  assert.match(home, /useRemoteThreadListRuntime/);
  assert.match(home, /useAISDKRuntime/);
  assert.match(home, /AssistantChatTransport/);
  assert.match(home, /createSimpleTitleAdapter/);
  assert.match(home, /FormattedLocalHistoryAdapter/);
  assert.match(home, /withFormat/);
  assert.match(home, /ThreadListPrimitive/);
  assert.match(home, /ComposerPrimitive/);
  assert.match(home, /symphonia\.clarise\.provider\.\$\{repoKey\}/);
  assert.match(home, /symphonia\.clarise\.modelProfile\.\$\{repoKey\}/);
  assert.match(home, /codex_app_server/);
  assert.match(home, /modelProfile/);
  assert.match(home, /\/codebase/);
  assert.match(home, /\/new-project/);
  assert.match(home, /\/verify-work/);
  assert.match(home, /View in workspace/);
  assert.doesNotMatch(home, /workspace\?created=private/);
  assert.match(home, /Private/);
  assert.match(home, /\/milestone/);
  assert.match(home, /\/workflow/);
  assert.match(home, /description: "Start a milestone, requirement, plan, and first task brief."/);
  assert.match(home, /composer\.setText\(`\$\{item\.command\} `\)/);
  assert.doesNotMatch(home, /Milestone: Project foundation \| Goal:/);
  assert.doesNotMatch(home, /Task brief: First execution slice \| Goal:/);
  assert.doesNotMatch(home, new RegExp("g" + "sd", "i"));

  const answerSurface = home.slice(
    home.indexOf("function ClariseMessage"),
    home.indexOf("function ClariseComposer"),
  );
  assert.doesNotMatch(answerSurface, /rounded-\[8px\]/);
});

test("Clarise chat route uses AI SDK streams and Codex extraction without prohibited writes", async () => {
  const route = await source("app/api/repositories/[repoKey]/clarise/chat/route.ts");
  const service = await source("services/symphonia_service/lib/symphonia_service/http_server.ex");

  assert.match(route, /createUIMessageStreamResponse/);
  assert.match(route, /extractPlanWithCodex/);
  assert.match(route, /\/clarise\/extract/);
  assert.match(route, /data-artifact_result/);
  assert.match(route, /data-missing_fields/);
  assert.match(route, /ensureWorkspaceFiles/);
  assert.match(route, /\/workspace\/initialize/);
  assert.match(route, /\/spec-workspace\/initialize/);
  assert.match(route, /codebase_map/);
  assert.match(route, /model_profile/);
  assert.match(route, /modelProfile/);
  assert.match(route, /provider_not_connected/);
  assert.match(route, /create_private_artifact/);
  assert.match(service, /ArtifactExtractor\.extract/);
  assert.doesNotMatch(route, /\/api\/github/);
  assert.doesNotMatch(route, /coding-assistant/);
  assert.doesNotMatch(route, /open-pull-request/);
  assert.doesNotMatch(route, /transcript/i);
});

test("run progress SSE stays bounded and off the task board", async () => {
  const route = await source(
    "app/api/repositories/[repoKey]/tasks/[taskKey]/runs/[runId]/events/route.ts",
  );
  const taskPage = await source("components/task-page.tsx");
  const tasksView = await source("components/tasks-view.tsx");

  assert.match(route, /export const maxDuration = 300/);
  assert.match(route, /const MAX_STREAM_SECONDS = 240/);
  assert.match(route, /const POLL_INTERVAL_MS = 2000/);
  assert.match(route, /const MAX_ATTEMPTS = Math\.floor/);
  assert.match(route, /attempt < MAX_ATTEMPTS/);
  assert.doesNotMatch(route, /attempt < 180/);
  assert.match(route, /last-event-id/);
  assert.match(route, /retry: 3000/);

  assert.match(taskPage, /new EventSource/);
  assert.doesNotMatch(tasksView, /EventSource/);
  assert.doesNotMatch(tasksView, /fetchCodingAssistantRunEvents/);
});

test("assistant-ui dependencies and React peer range are installed intentionally", async () => {
  const manifest = JSON.parse(await source("package.json"));

  assert.match(manifest.dependencies["@assistant-ui/react"], /^\^0\./);
  assert.match(manifest.dependencies["@assistant-ui/react-ai-sdk"], /^\^1\./);
  assert.match(manifest.dependencies.ai, /^\^6\./);
  assert.match(manifest.dependencies["@ai-sdk/react"], /^\^3\./);
  assert.match(manifest.dependencies.react, /^\^19\.2\./);
  assert.match(manifest.dependencies["react-dom"], /^\^19\.2\./);
  assert.match(manifest.devDependencies["@types/react"], /^\^19\.2\./);
});

test("Clarise planner asks for missing fields and supports small schema-complete batches", async () => {
  const { normalizeClarisePlan, planClariseResponse } = await loadTs(
    "lib/clarise-chat.ts",
    "clarise-chat.cjs",
  );

  const missingPlan = planClariseResponse([{ role: "user", content: "Create a milestone" }]);
  assert.equal(missingPlan.artifactDrafts.length, 0);
  assert.deepEqual(
    missingPlan.missingFields.map((field) => `${field.kind}:${field.field}`).sort(),
    ["milestone:goal", "milestone:title"],
  );

  const slashCommandPlan = planClariseResponse([{ role: "user", content: "/new-project" }]);
  assert.equal(slashCommandPlan.artifactDrafts.length, 0);
  assert.deepEqual(
    slashCommandPlan.missingFields.map((field) => `${field.kind}:${field.field}`).sort(),
    ["milestone:goal", "plan:plan", "requirements:requirement", "task_brief:goal"],
  );

  const batchPlan = planClariseResponse([
    {
      role: "user",
      content:
        "Milestone: Clarise landing | Goal: Make repo home chat-first\nRequirement: Durable memory | Requirement: Preserve project memory privately\nPlan: Chat-first flow | Plan: Create docs before runs\nDecision: Private artifacts | Decision: Do not persist transcripts\nTask brief: Set up WORKFLOW.md | Goal: Prepare private setup steps",
    },
  ]);

  assert.equal(batchPlan.artifactDrafts.length, 5);
  assert.deepEqual(
    batchPlan.artifactDrafts.map((draft) => draft.kind).sort(),
    ["decision", "milestone", "plan", "requirements", "task_brief"],
  );
  assert.ok(batchPlan.artifactDrafts.every((draft) => draft.metadata.private === true));
  assert.ok(
    batchPlan.artifactDrafts
      .filter((draft) => ["decision", "plan", "requirements"].includes(draft.kind))
      .every((draft) => draft.linkToBatchMilestone === true),
  );

  const codexPlan = normalizeClarisePlan({
    assistantText: "Saving milestone.",
    artifactDrafts: [
      {
        kind: "milestone",
        title: "Codex extraction",
        body: "# Milestone - Codex extraction",
        metadata: { private: false },
        confirmation: "Created private milestone.",
      },
    ],
    missingFields: [],
  });

  assert.equal(codexPlan.artifactDrafts.length, 1);
  assert.equal(codexPlan.artifactDrafts[0].metadata.private, true);
  assert.equal(codexPlan.artifactDrafts[0].metadata.source, "clarise_chat");
});

test("spec workspace supports private task brief artifacts", async () => {
  const model = await source("lib/repository-model.ts");
  const store = await source("services/symphonia_service/lib/symphonia_service/spec_workspace/store.ex");
  const templates = await source("services/symphonia_service/lib/symphonia_service/spec_workspace/templates.ex");
  const http = await source("services/symphonia_service/lib/symphonia_service/http_server.ex");
  const workspacePage = await source("app/r/[repoKey]/workspace/page.tsx");
  const workspaceIndex = await source("components/spec-workspace-index.tsx");

  assert.match(model, /\| "task_brief"/);
  assert.match(store, /"task_brief" => \{"task", "symphonia\/task-briefs"\}/);
  assert.match(store, /"requirements" => \{"requirement", "symphonia\/requirements"\}/);
  assert.match(templates, /def body\("task_brief"/);
  assert.match(http, /"requirements"/);
  assert.match(http, /"plans"/);
  assert.match(http, /"task-briefs"/);
  assert.doesNotMatch(workspacePage, /SpecWorkspaceIndex/);
  assert.match(workspacePage, /notFound\(\)/);
  assert.match(workspaceIndex, /Private/);
});

test("Clarise milestone compiler supports editable selected task proposals", async () => {
  const loop = await source("components/clarise-milestone-loop.tsx");
  const compiler = await source(
    "services/symphonia_service/lib/symphonia_service/clarise/plan_to_task_compiler.ex",
  );
  const markdown = await source("services/symphonia_service/lib/symphonia_service/markdown.ex");

  assert.match(loop, /Compile tasks/);
  assert.match(loop, /Create selected/);
  assert.match(loop, /Create all/);
  assert.match(loop, /Harness readiness/);
  assert.match(loop, /selectedProposalItemIds/);
  assert.match(loop, /acceptance_criteria/);
  assert.match(loop, /review_expectations/);
  assert.match(loop, /Move task up/);
  assert.match(loop, /Move task down/);

  assert.match(compiler, /proposal_items/);
  assert.match(compiler, /selectedProposalItemIds/);
  assert.match(compiler, /@generation_version "v2"/);
  assert.match(compiler, /@legacy_generation_versions \["v1"\]/);
  assert.match(compiler, /source_discussion/);
  assert.match(compiler, /Task proposal is required before creating tasks/);
  assert.match(compiler, /not selected or already created/);
  assert.match(markdown, /proposal_items/);
  assert.match(markdown, /JSON\.encode!\(values\)/);
});
