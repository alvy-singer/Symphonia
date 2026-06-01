# Privacy Threat Model + Data Inventory V1

V1 private storage is service-readable local state beside the registry. It is not zero-knowledge and it is not end-to-end encrypted. The current boundary is repo-private, provider-scoped, browser-access-controlled, audit-sanitized, and GitHub-export-explicit.

## Destinations

- `local_private_storage`: Service-readable state beside the registry, including private workspace blobs, run records, audit files, and export metadata.
- `managed_repository`: Files inside the user repository worktree, such as WORKFLOW.md and task Markdown.
- `browser_ui`: Rendered through repository access checks and public payload shapers.
- `providers`: Provider-scoped context only: task brief, WORKFLOW.md, explicitly linked artifacts, review notes, and handoff summaries.
- `github`: Repository code, WORKFLOW.md, task Markdown, PR bodies, and explicit PR-based private workspace export snapshots.
- `audit_logs`: Allowlisted metadata only; no raw bodies, logs, transcripts, provider output, paths, env values, thread ids, or turn ids.

## Data Surfaces

| Surface | Sensitivity | Local private | Managed repo | Browser UI | Providers | GitHub | Audit logs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `private_workspace_artifacts` | private_content | allowed | blocked | conditional | conditional | conditional | blocked |
| `private_workspace_evidence` | private_evidence | allowed | blocked | conditional | blocked | blocked | blocked |
| `raw_run_records` | private_runtime_material | allowed | blocked | blocked | blocked | blocked | blocked |
| `public_run_events` | public_safe_status | conditional | blocked | allowed | blocked | blocked | blocked |
| `task_markdown` | repo_visible_workflow | blocked | allowed | allowed | conditional | allowed | blocked |
| `handoffs` | review_safe_summary | allowed | allowed | allowed | conditional | conditional | blocked |
| `run_summaries` | private_review_summary | allowed | blocked | allowed | conditional | conditional | blocked |
| `pr_bodies` | public_review_text | conditional | blocked | allowed | blocked | allowed | blocked |
| `audit_events` | public_safe_metadata | allowed | blocked | allowed | blocked | blocked | allowed |
| `provider_context_packs` | provider_scoped_private_context | blocked | blocked | blocked | allowed | blocked | blocked |
| `clarise_chat_derived_artifacts` | private_content | allowed | blocked | allowed | conditional | conditional | blocked |
| `workflow_files` | repo_visible_execution_contract | blocked | allowed | allowed | allowed | allowed | conditional |
| `github_export_snapshots` | public_snapshot | allowed | blocked | allowed | blocked | allowed | blocked |
| `review_notes` | repo_visible_review_text | blocked | allowed | allowed | conditional | allowed | blocked |

## V1 Enforcement Notes

- Private artifact bodies and evidence stay in private workspace state unless rendered to an authorized browser view, sent through linked provider context, or explicitly exported through a review branch and PR.
- Raw run records, provider output, transcripts, thread ids, turn ids, workspace paths, and local validation logs stay in local private storage.
- Public run events expose curated labels, safe messages, run ids, task keys, review branches, curated summary ids, and evidence ids.
- Provider context packs must not include raw run records, audit events, raw provider output, local private paths, env values, or unrelated private artifacts.
- Audit logs store allowlisted metadata and sanitized summaries only.
- GitHub receives private workspace material only through explicit export snapshots. Exports are sanitized, revision-specific, PR-based, and not live-synced.

## Leak Fixtures

The test fixture set covers local paths, env assignments, tokenized URLs, token-like values, provider output markers, raw log markers, transcripts, thread ids, turn ids, and evidence blob markers.
