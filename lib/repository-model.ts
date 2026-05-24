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
  user?: {
    id?: number;
    login?: string;
    avatarUrl?: string;
    url?: string;
  };
  connectedAt?: string;
  accessTokenExpiresAt?: string;
  refreshTokenExpiresAt?: string;
  installationUrl?: string;
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
  linkedAt?: string;
}

export interface RepositoryGitHubState {
  connection: GitHubConnectionState;
  detectedRemote?: GitHubRemote | null;
  link?: GitHubRepositoryLink | null;
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
