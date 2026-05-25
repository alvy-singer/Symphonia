# Spec Workspace

Symphonia is being reframed as a repository planning workspace. The current app still keeps the older repository workspace for tasks, reviews, run summaries, and `WORKFLOW.md`; the Spec Workspace extends that existing file shell with semantic Markdown files for planning and product intent.

## Repo-backed files

The spec workspace lives under `symphonia/` in the opened repository:

```text
symphonia/
  codebase/
    map.md
    conventions.md
    architecture.md
  milestones/
  discussions/
  requirements/
  plans/
  decisions/
  tasks/
  reviews/
  run-summaries/
```

Each spec file is Markdown with a metadata block:

```markdown
---
type: milestone
id: milestone-001
title: Untitled milestone
status: draft
created_at: 2026-05-25T00:00:00Z
updated_at: 2026-05-25T00:00:00Z
source: clarise
---
```

Spec statuses are separate from task statuses:

- `draft`
- `in_discussion`
- `ready_for_approval`
- `approved`
- `archived`

## Local and Private Data

The repository stores curated Markdown only. Raw Coding Assistant logs and other local operational files stay outside the repository. Run summaries can be committed when they are intentionally written as human-readable Markdown.

## Semantic Layer

The frontend treats these files as normal workspace Markdown, but the service indexes their frontmatter so the UI can show product meaning: Codebase, Milestones, Discussions, Requirements, Plans, and Decisions. Clarise-created files are not hidden implementation files; they are the same repo-backed workspace artifacts users can open and edit.

## Specs Versus Tasks

Spec files describe intent, context, decisions, requirements, and plans. They are not executable task records.

Task files under `symphonia/tasks/` keep the existing task lifecycle: To-do, In Progress, In Review, Completed, Paused, and Canceled. Coding Assistant background runs continue to work from tasks, not directly from milestones or plans.

## Later Work

This foundation lets Clarise create and update durable workspace files first. Milestone 9 adds the milestone-planning loop and plan approval. Later milestones can add plan-to-task compilation so approved plans can become Coding Assistant tasks.
