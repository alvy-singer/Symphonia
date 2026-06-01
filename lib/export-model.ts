export type WorkspaceArtifactExportStatus =
  | "never_exported"
  | "linked"
  | "changed_since_export"
  | "pr_open"
  | "conflict"
  | "unlinked";

export type PullRequestState = "open" | "merged" | "closed" | "unknown" | "unlinked";

export interface WorkspaceArtifactExport {
  id: string;
  artifactId: string;
  artifactKind: string;
  provider: "github";
  targetRepo: string;
  targetPath: string;
  baseBranch: string;
  exportBranch?: string;
  exportedRevisionId?: string;
  lastExportedAt?: string;
  pullRequestUrl?: string;
  pullRequestNumber?: number;
  pullRequestState?: PullRequestState;
  status: WorkspaceArtifactExportStatus;
  createdAt?: string;
  updatedAt?: string;
}

export interface ExportPreview {
  artifactId: string;
  artifactKind?: string;
  revisionId: string;
  targetRepo?: string;
  targetPath: string;
  baseBranch: string;
  operation: "create" | "update" | "conflict";
  markdownPreview: string;
  changedSinceLastExport: boolean;
  warnings: string[];
}
