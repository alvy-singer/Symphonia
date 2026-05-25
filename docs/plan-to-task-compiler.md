# Plan-to-Task Compiler

Clarise turns an approved milestone plan into a reviewed task proposal, then creates task Markdown files only after the user confirms.

## What Clarise Reads

For an approved milestone, Clarise reads:

- `symphonia/milestones/milestone-00N.md`
- the linked discussion
- the linked requirements
- the linked plan
- linked decisions

The milestone must be approved before task generation is available.

## What Clarise Writes

Clarise first persists a proposal:

- `symphonia/task-proposals/milestone-00N-task-proposal.md`

The proposal includes the source milestone, source plan, generation id, proposed task list, dependency order, review expectations, and any created task keys.

After the user confirms, Clarise writes tasks under:

- `symphonia/tasks/`

Generated tasks use the existing task lifecycle and start as To-do. They include source metadata such as `source_milestone`, `source_plan`, `generation_id`, and `proposal_item_id` so repeated confirmation of the same proposal does not create duplicates.

After task creation, the workspace routes the lead to the task board filtered to the source milestone. The handoff stops there: reviewing or assigning a task remains a deliberate next action.

## Review Before Creation

The workspace shows the proposed task breakdown before task files are written. Full inline proposal editing is not required in this milestone. After creation, users can edit task Markdown through the existing task pages.

## Dependencies

Proposal items use proposal ids while they are still drafts, such as:

```text
milestone-001-task-001
```

When tasks are created, Clarise resolves those draft dependencies into final task keys, such as:

```text
SYM-8
```

## Vague Plans

If an approved plan does not contain enough implementation detail, Clarise creates clarification and planning tasks instead of inventing precise implementation work.

## Boundaries

This milestone does not start Coding Assistant work automatically. It does not add GitHub or Linear projection. It stops at approved plan, reviewed task proposal, and repo-backed To-do task files.
