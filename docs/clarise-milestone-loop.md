# Clarise Milestone Loop

Clarise helps turn a vague product idea into repo-backed Markdown artifacts that the user can review and edit in the workspace.

## What Clarise Creates

The loop creates linked Markdown files under `symphonia/`:

- `symphonia/milestones/milestone-00N.md`
- `symphonia/discussions/milestone-00N-discussion.md`
- `symphonia/requirements/milestone-00N-requirements.md`
- `symphonia/plans/milestone-00N-plan.md`
- `symphonia/decisions/decision-00N.md`

The milestone metadata links the discussion, requirements, plan, and decisions so the workspace can keep related files together.

## Loop Steps

1. Start a new milestone.
2. Discuss the milestone with guided Clarise questions.
3. Generate requirements from the milestone and discussion.
4. Generate an implementation plan from the requirements.
5. Record decisions linked to the milestone.
6. Approve the milestone after discussion, requirements, and plan files exist.

Generation is deterministic in this milestone. Clarise writes editable Markdown, not hidden app state.

## Statuses

Milestone and spec artifact statuses are separate from task statuses.

Spec artifact statuses:

- `draft`
- `in_discussion`
- `requirements_ready`
- `plan_ready`
- `ready_for_approval`
- `approved`
- `archived`

Task statuses remain unchanged:

- To-do
- In Progress
- In Review
- Completed
- Paused
- Canceled

## Approved Plans

An approved milestone means the milestone has enough discussion, requirements, and plan context to move forward. It does not create tasks yet, and it does not start Coding Assistant work.

Later milestones can add plan-to-task generation and validation from approved plans.
