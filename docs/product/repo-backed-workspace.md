# Symphonia Repo-Backed Workspace Product Spec

## Product Baseline

Symphonia is a repository-backed work workspace. The top-level workspace object is a Repository. Projects, tasks, docs, reviews, decisions, run summaries, and workflow live inside or alongside that repository as readable Markdown.

The product should feel familiar to users of Notion, Obsidian, and Craft: a database row opens into a document, properties drive list and board views, and the document body remains the human-readable source of context. The difference is that Symphonia stores the durable work record next to the code.

Locked model:

- First screen: Repositories and Add Repository.
- Repository home: task board/list, board by default, last selected mode remembered per repository.
- Board cards: tasks only.
- Status semantics: coding-run-driven, not generic Kanban.
- Workflow: root `WORKFLOW.md` only.
- Durable task source: `symphonia/tasks/*.md`.
- Durable project-management docs: configurable, with `symphonia/` as the friendly default.
- Raw run logs: local/private only.
- Curated run summaries, review notes, and task history: allowed in repository Markdown.

## Accessibility Rules

Every screen must answer four questions without requiring technical background:

- What am I looking at?
- Why does it matter?
- What is safe or unsafe right now?
- What can I do next?

User-facing UI must use plain labels:

- Task, not work packet.
- Coding Assistant, not provider or runner.
- Workflow, not substrate.
- Run summary, not event stream.
- Validation, not evidence boundary.
- Safety log, not proof ledger.

Internal values must not leak into the UI. For example, users see `In Progress`, never `in_progress`, `pending_review`, or `timed_out`.

## Task Lifecycle

Tasks use six stable user-facing statuses:

- To-do
- In Progress
- In Review
- Paused
- Completed
- Canceled

Implementation uses stable internal enum values:

- `todo`
- `in_progress`
- `in_review`
- `paused`
- `completed`
- `canceled`

Paused tasks use a fixed reason badge plus optional explanation:

- `run_failed` -> Run failed
- `waiting_for_user` -> Waiting for user
- `blocked_by_setup` -> Blocked by setup
- `waiting_for_sync` -> Waiting for sync
- `needs_clarification` -> Needs clarification

Status is automatic and coding-run-driven. Users do not manually edit status. They perform actions such as Assign to Coding Assistant, Request changes, Open Pull Request, or Cancel task, and Symphonia updates status from those events.

## Review Loop

`In Review` means there is a concrete handoff for the user to inspect. The default handoff is intentionally minimal:

- Summary of changes
- Files changed
- Next review action

The default review view prioritizes:

- Summary of changes
- Files changed
- Approve / Request changes

Approval accepts the current handoff. The task becomes Completed only when the workflow reaches terminal success. For PR-based workflows:

1. Coding Assistant produces handoff.
2. Task moves to `In Review`.
3. User approves handoff.
4. If a PR is required, task stays `In Review` with next step Open Pull Request.
5. Pull request opens, task stays `In Review` with PR Open.
6. Pull request merges, task becomes `Completed`.
7. Linked GitHub issues update or close automatically when enabled.

Request changes sends the task back to `In Progress` and resumes the Coding Assistant automatically. Users write feedback naturally. Clarise preserves the original feedback on the task page, structures it into a checklist, and only the checklist is passed to the Coding Assistant continuation.

## Clarise

Clarise is the workspace assistant. She is separate from Coding Assistants such as Codex, Claude, or Cursor.

Locked behavior:

- Clarise lives in a small bottom-right space.
- Clarise can directly perform safe workspace actions.
- Risky or external-impacting actions require clear confirmation boundaries.
- Clarise uses permissioned context scopes that last for the current app session.
- Clarise has curated memory only.
- Larger Clarise outputs open as editable drafts in the main workspace editor before saving.
- Review feedback is structured by Clarise into requested changes, while preserving the original feedback in task history.

## Research Notes

Notion is relevant for the row-as-page model: database entries have properties and open into content pages.

Obsidian Bases is closer to the target persistence model: Markdown files and their properties can become database-like views without moving data into a SaaS database.

Circle and Linear are relevant visual references for compact grouped work views, but Symphonia must not become a generic Kanban board. The board is a Coding Assistant work board. Its statuses come from Symphonia/Symphony workflow semantics.

OpenAI Symphony is the orchestration reference. Its Elixir implementation frames work as tracker items converted into isolated autonomous runs and uses `WORKFLOW.md` as the workflow contract. Symphonia keeps that workflow-file idea, but wraps it in a repository-backed workspace product.

## Non-Goals For Milestone 1

- No readiness check, harness screen, repo scanner, or setup gate.
- No full Linear implementation.
- No arbitrary visual workflow builder.
- No broad two-way sync.
- No raw agent event log persistence in the repository.
- No manual status editing.
- No full projects/docs/decisions roundtrip beyond task-linked references.
