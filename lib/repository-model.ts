export interface WorkspaceState {
  initialized: boolean;
  missingDirectories: string[];
  workflow: {
    exists: boolean;
    valid: boolean;
  };
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
