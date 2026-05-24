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
  last_task_number?: number;
  lastTaskNumber?: number;
  taskCount?: number;
  workspace?: WorkspaceState;
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
