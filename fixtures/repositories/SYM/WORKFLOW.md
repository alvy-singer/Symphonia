---
tracker:
  kind: github
workflow:
  requires_pr: true
  retry_limit: 2
assistant:
  default: codex
---

# WORKFLOW.md

Coding Assistants work from repo-backed task Markdown files.

Default flow:

1. Start work from a task in `symphonia/tasks/`.
2. Produce a minimal review handoff.
3. Wait for human approval.
4. Open a pull request after approval.
5. Complete the task when the pull request is merged.
