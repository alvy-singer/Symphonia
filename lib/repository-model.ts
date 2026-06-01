export interface WorkspaceState {
  initialized: boolean;
  missingDirectories: string[];
  workflow: {
    exists: boolean;
    valid: boolean;
  };
}

export type SpecArtifactType =
  | "codebase_map"
  | "codebase_conventions"
  | "codebase_architecture"
  | "milestone"
  | "discussion"
  | "requirements"
  | "plan"
  | "task_proposal"
  | "task_brief"
  | "decision"
  | "run_summary";

export type SpecArtifactStatus =
  | "draft"
  | "in_discussion"
  | "requirements_ready"
  | "plan_ready"
  | "ready_for_approval"
  | "approved"
  | "created"
  | "archived";

export interface SpecWorkspaceState {
  exists: boolean;
  initialized: boolean;
  missingDirectories: string[];
  missingDefaultArtifacts: SpecArtifactType[];
  statuses: SpecArtifactStatus[];
}

export interface SpecArtifact {
  type: SpecArtifactType;
  id: string;
  title: string;
  status: SpecArtifactStatus;
  source?: string;
  createdAt?: string;
  updatedAt?: string;
  path: string;
  latestRevisionId?: string;
  exportStatus?:
    | "never_exported"
    | "linked"
    | "changed_since_export"
    | "pr_open"
    | "conflict"
    | "unlinked";
  legacyRepoPath?: string;
  reviewBranch?: string;
  githubPrUrl?: string;
  metadata: Record<string, unknown> & {
    type: SpecArtifactType;
    id: string;
    title?: string;
    status?: SpecArtifactStatus;
    created_at?: string;
    updated_at?: string;
    source?: string;
    latest_revision_id?: string;
    export_status?: string;
    legacy_repo_path?: string;
    review_branch?: string;
    github_pr_url?: string;
    discussion?: string;
    requirements?: string;
    plan?: string;
    decisions?: string[];
    related_milestone?: string;
    approved_at?: string;
    source_milestone?: string;
    source_plan?: string;
    source_requirements?: string;
    source_discussion?: string;
    source_decisions?: string[];
    generated_by?: string;
    generation_id?: string;
    created_tasks?: string[];
    proposal_items?: unknown[];
    blockers?: string[];
    warnings?: string[];
  };
  body: string;
}

export type SpecArtifactSummary = Omit<SpecArtifact, "body">;

export interface SpecWorkspaceSection {
  label: string;
  types: SpecArtifactType[];
  artifacts: SpecArtifactSummary[];
}

export interface SpecWorkspacePayload {
  state: SpecWorkspaceState;
  sections: SpecWorkspaceSection[];
  legacy?: LegacyWorkspaceArtifact[];
  evidence?: PrivateWorkspaceEvidence[];
}

export interface LegacyWorkspaceArtifact {
  type: SpecArtifactType;
  kind: SpecArtifactType;
  id: string;
  title: string;
  status: SpecArtifactStatus;
  legacyRepoPath: string;
  imported?: boolean;
  privateArtifactId?: string;
  exportStatus?: SpecArtifact["exportStatus"];
}

export interface PrivateWorkspaceEvidence {
  kind: string;
  id: string;
  title?: string;
  status?: string;
  artifactId?: string;
  runId?: string;
  createdAt?: string;
  updatedAt?: string;
  payload?: Record<string, unknown>;
}

export interface MarkdownPage {
  type: "page";
  id: string;
  title: string;
  body: string;
  path: string;
  parentId?: string;
  icon?: string;
  cover?: string;
  isArchived: boolean;
  isPublished: boolean;
  createdAt?: string;
  updatedAt?: string;
  metadata: Record<string, unknown> & {
    type: "page";
    id: string;
    title?: string;
    parent_id?: string;
    icon?: string;
    cover?: string;
    archived?: boolean;
    published?: boolean;
    created_at?: string;
    updated_at?: string;
  };
}

export interface MarkdownPagesPayload {
  pages: MarkdownPage[];
}

export interface RepositorySummary {
  key: string;
  name: string;
  path: string;
  github?: GitHubRepositoryLink | null;
  automation?: RepositoryAutomationState | null;
  remoteExecutionAllowed?: boolean;
  sandboxExecutionAllowed?: boolean;
  sandboxProvider?: string | null;
  sandboxProviderReadiness?: {
    configured?: boolean;
    ready?: boolean;
    status?: string;
    reason?: string | null;
    provider?: string | null;
    label?: string;
    credential?: string;
    workspaceMode?: string;
    credentialMode?: string;
    egressMode?: string;
    operations?: {
      provider?: string;
      lastSmokeStatus?: "passed" | "failed" | "never_run" | "running" | string;
      lastSmokeAt?: string;
      reasonCode?: string;
      cleanupWarning?: boolean;
      workspaceMode?: string;
      lastCleanupStatus?: string;
      lastCleanupAt?: string;
      lastCleanupReasonCode?: string;
    };
  };
  allowedRunnerIds?: string[];
  allowedSandboxProviders?: string[];
  allowedCodingAssistantProviders?: string[];
  requireTrustedRunner?: boolean;
  secretScopesAllowed?: string[];
  last_task_number?: number;
  lastTaskNumber?: number;
  taskCount?: number;
  workspace?: WorkspaceState;
}

export interface RepositoryAutomationState {
  enabled: boolean;
  provider?: "codex_app_server" | "codex" | "local_demo" | string;
  enabledAt?: string;
  disabledAt?: string;
}

export type CodingAssistantProviderStatusValue =
  | "ready"
  | "not_configured"
  | "blocked"
  | "disabled"
  | "experimental";

export interface CodingAssistantProviderStatus {
  id: string;
  label: string;
  configured: boolean;
  ready: boolean;
  runnable: boolean;
  runnableByHarness: boolean;
  manualOnly?: boolean;
  executionMode?: string;
  workspaceProvider?: string;
  status: CodingAssistantProviderStatusValue;
  reason: string;
  capabilities: Record<string, boolean>;
  missingCapabilities: string[];
}

export interface CodingAssistantProviderCatalog {
  defaultProvider?: string;
  runnableProvider: string;
  providers: CodingAssistantProviderStatus[];
}

export interface GitHubConnectionState {
  connected: boolean;
  authMode?: "app_installation" | "device_user_token";
  user?: {
    id?: number;
    login?: string;
    avatarUrl?: string;
    url?: string;
  };
  connectedAt?: string;
  installationUrl?: string;
  manageUrl?: string;
  appConfigured?: boolean;
  deviceFallbackEnabled?: boolean;
  installed?: boolean;
  installedRepositoriesCount?: number;
  installations?: GitHubInstallation[];
}

export interface GitHubInstallation {
  id: number | string;
  account?: {
    login?: string;
    type?: string;
    url?: string;
  };
  repositorySelection?: string;
  repositoryCount?: number;
  updatedAt?: string;
}

export interface GitHubInstalledRepository {
  owner: string;
  name: string;
  fullName?: string;
  repoId?: number;
  url?: string;
  cloneUrl?: string;
  defaultBranch?: string;
  installationId?: number | string;
  accountLogin?: string;
  accountType?: string;
}

export interface GitHubRemote {
  owner: string;
  name: string;
  url: string;
  remoteUrl: string;
  defaultBranch?: string | null;
}

export interface GitHubRepositoryLink {
  owner?: string;
  name?: string;
  repoId?: number;
  url?: string;
  cloneUrl?: string;
  defaultBranch?: string;
  installationId?: number;
  authMode?: "app_installation" | "device_user_token";
  linkedAt?: string;
}

export interface RepositoryGitHubState {
  connection: GitHubConnectionState;
  detectedRemote?: GitHubRemote | null;
  link?: GitHubRepositoryLink | null;
  access?: {
    state: "linked" | "available" | "missing" | "no_remote" | string;
    message?: string;
  };
}

export interface WorkflowTemplate {
  id: string;
  label: string;
  description: string;
  body: string;
}

export interface WorkflowFile {
  exists: boolean;
  path: "WORKFLOW.md";
  body: string;
  templates: WorkflowTemplate[];
}

export type RepositoryReadinessState = "ready" | "needs_setup" | "blocked" | "warning";

export type RepositoryReadinessCheckStatus =
  | "passed"
  | "warning"
  | "failed"
  | "not_checked";

export type RepositoryReadinessCategory =
  | "workspace"
  | "planning"
  | "automation"
  | "provider"
  | "runner"
  | "sandbox"
  | "secrets"
  | "validation"
  | "github"
  | "review";

export type RepositoryReadinessActionKind =
  | "navigate"
  | "run_check"
  | "create_file"
  | "connect"
  | "enable";

export interface RepositoryReadinessAction {
  id: string;
  label: string;
  href?: string;
  kind: RepositoryReadinessActionKind;
}

export interface RepositoryReadinessCheck {
  id: string;
  label: string;
  status: RepositoryReadinessCheckStatus;
  category: RepositoryReadinessCategory;
  detail: string;
  action?: RepositoryReadinessAction;
}

export interface RepositoryScannerAdvisory {
  detected: string[];
  files: string[];
  scripts: string[];
  suggestedValidation: {
    label: string;
    command: string;
  }[];
}

export interface RepositoryReadiness {
  state: RepositoryReadinessState;
  summary: string;
  checks: RepositoryReadinessCheck[];
  nextActions: RepositoryReadinessAction[];
  scan?: RepositoryScannerAdvisory;
}
