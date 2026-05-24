# Filesystem-Backed Symphonia Architecture

## Baseline

Milestone 1 must prove that task lifecycle state is backed by real Markdown files, not local mock state. The first vertical slice is a service-backed task lifecycle demo using `symphonia/tasks/*.md`.

The Next app remains the frontend shell. An Elixir service owns repository filesystem access, Markdown parsing/serialization, lifecycle transitions, and future orchestration. The frontend talks to a service-shaped API and can fall back to fixture files during local development.

## Repository Layout

Canonical workflow file:

```text
WORKFLOW.md
```

Friendly default document root:

```text
symphonia/
  projects/
  tasks/
  docs/
  reviews/
  decisions/
  run-summaries/
  templates/
```

Milestone 1 implements only:

```text
WORKFLOW.md
symphonia/tasks/*.md
```

## Task Markdown Schema

Task files use Obsidian-like YAML frontmatter plus Markdown body content.

```markdown
---
key: SYM-120
title: Improve repository overview
status: todo
priority: high
project: Repository workspace
assistant: Codex
paused_reason:
github_issue: https://github.com/agora-creations/symphonia/issues/412
github_issue_state: open
github_pr:
github_pr_state:
github_sync_enabled: true
review_approved: false
review_summary:
files_changed:
  - app/page.tsx
next_review_action:
updated_at: 2026-05-24T10:00:00Z
---

# Improve repository overview

## Goal

Make the repository overview a task board/list backed by Markdown.
```

Required implementation fields:

- `key`
- `title`
- `status`
- `priority`
- `updated_at`

Optional implementation fields:

- `project`
- `assistant`
- `paused_reason`
- `paused_explanation`
- `github_issue`
- `github_issue_state`
- `github_pr`
- `github_pr_state`
- `github_sync_enabled`
- `review_approved`
- `review_summary`
- `files_changed`
- `next_review_action`

Internal statuses:

- `todo`
- `in_progress`
- `in_review`
- `paused`
- `completed`
- `canceled`

Paused reasons:

- `run_failed`
- `waiting_for_user`
- `blocked_by_setup`
- `waiting_for_sync`
- `needs_clarification`

## Lifecycle Events

The service accepts named lifecycle events and rewrites the same task Markdown file.

- `start`: status -> `in_progress`.
- `submit_review`: status -> `in_review`; writes minimal handoff fields.
- `fail_run`: status -> `paused`; `paused_reason` -> `run_failed`.
- `approve`: marks the handoff accepted. If no PR step remains, status -> `completed`; otherwise status stays `in_review`.
- `request_changes`: appends original feedback and Clarise checklist to the body; status -> `in_progress`.
- `open_pr`: stores PR URL/state; status stays `in_review`.
- `merge_pr`: PR state -> `merged`; status -> `completed`; closes/updates linked GitHub issue when enabled.
- `cancel`: status -> `canceled`.

Review feedback serialization must preserve both:

- Original freeform feedback.
- Clarise-structured checklist.

Only the checklist is passed to the simulated Coding Assistant continuation.

## Service Boundary

The Elixir service should expose service-shaped operations:

- List repositories.
- List tasks for a repository.
- Read one task.
- Patch title/body/frontmatter fields for one task.
- Apply lifecycle event to one task.

The first implementation may run against fixture repositories. Arbitrary user-selected repository access is a later permission and product-shell problem.

## GitHub Boundary

Milestone 1 is GitHub-first but event-limited:

- Store linked GitHub issue URL/number in task frontmatter.
- Store linked PR URL/number in task frontmatter.
- Simulate or detect PR opened.
- Simulate or detect PR merged.
- On `completed`, close/update linked GitHub issue only if enabled.

Do not implement broad two-way GitHub sync in Milestone 1.

The architecture must treat GitHub writes carefully:

- PR creation and issue updates require write access.
- Writes may trigger notifications.
- Repeated writes can hit secondary rate limits.
- GitHub pull requests are also issue-like resources in parts of the API, so issue IDs and PR IDs must not be conflated.

## Frontend Integration

The current board/list UI should load task data from the service API instead of `data/mock.ts`.

Frontend rules:

- Display labels only, never raw enum values.
- Keep board cards lightweight.
- Show paused reason badge when status is Paused.
- Show PR Open badge when a task has an open PR.
- Put lifecycle actions on the task page and allow compact demo actions on the board.
- Keep raw run logs out of repo-backed views.

## Validation

Milestone 1 is complete when:

- Elixir tests prove Markdown parse/serialize/body preservation.
- Elixir tests prove lifecycle transitions.
- Next build passes.
- A temporary or fixture repository task can be read, updated, and serialized back to Markdown.
- UI renders the six canonical labels with no raw internal status leakage.
