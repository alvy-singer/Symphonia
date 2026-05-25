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
  | "decision";

export type SpecArtifactStatus =
  | "draft"
  | "in_discussion"
  | "requirements_ready"
  | "plan_ready"
  | "ready_for_approval"
  | "approved"
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

export interface RepositorySummary {
  key: string;
  name: string;
  path: string;
  github?: GitHubRepositoryLink | null;
  last_task_number?: number;
  lastTaskNumber?: number;
  taskCount?: number;
  workspace?: WorkspaceState;
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
