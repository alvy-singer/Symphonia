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
  | "decision";

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
  metadata: Record<string, unknown> & {
    type: SpecArtifactType;
    id: string;
    title?: string;
    status?: SpecArtifactStatus;
    created_at?: string;
    updated_at?: string;
    source?: string;
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
