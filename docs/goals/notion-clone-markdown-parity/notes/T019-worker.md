# T019 Worker Receipt

## Outcome

Codebase, milestone, plan, decision, and related spec workspace artifacts now use the same Notion-like Markdown editor surface as generic pages.

## Changes

- Added a custom persistence hook to the shared Markdown editor so non-page documents can reuse the icon, cover, title, save-status, publish, action-menu, formatting-toolbar, and slash-command UI without writing through the generic pages store.
- Replaced the old spec artifact form editor with the shared Notion-like editor.
- Mapped spec artifact publish state onto existing artifact statuses and preserved title/body/icon/cover through the spec workspace API.
- Kept the ellipsis action available for workspace artifacts, with artifact status shown in the action menu instead of the generic page-delete action.

## Verification

- `npm run build` -> passed.
- `git diff --check` -> passed.
- `GET /r/sym/workspace/plan/plan-001` -> `200 OK`.
- `GET /api/repositories/SYM/spec-workspace/artifacts/plan/plan-001` -> `200 OK`.
- Runtime chunk for `/r/[repoKey]/workspace/[artifactType]/[artifactId]` includes `Add icon`, `Add cover`, `Publish`, `Heading 2`, `Type to filter`, and the workspace artifact slash-command placeholder.
