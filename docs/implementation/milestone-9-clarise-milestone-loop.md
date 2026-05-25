# Milestone 9 Clarise Milestone Loop

## Summary

Implemented a guided Clarise loop for establishing repo-backed milestones. Users can start a milestone, answer guided questions, generate requirements, generate a plan, record linked decisions, and approve the milestone after required artifacts exist.

## Files and Modules Added

- `SymphoniaService.Clarise.MilestoneLoop`
- `SymphoniaService.Clarise.MilestoneDiscussion`
- `SymphoniaService.Clarise.RequirementsBuilder`
- `SymphoniaService.Clarise.PlanBuilder`
- `SymphoniaService.Clarise.DecisionRecorder`
- `components/clarise-milestone-loop.tsx`
- `app/r/[repoKey]/workspace/page.tsx`

## APIs Added

- `POST /api/repositories/:repo/clarise/milestones/start`
- `POST /api/repositories/:repo/clarise/milestones/:milestone/discuss`
- `POST /api/repositories/:repo/clarise/milestones/:milestone/requirements`
- `POST /api/repositories/:repo/clarise/milestones/:milestone/plan`
- `POST /api/repositories/:repo/clarise/milestones/:milestone/decisions`
- `POST /api/repositories/:repo/clarise/milestones/:milestone/approve`

## UI Added

- Added `/r/[repoKey]/workspace` as the Spec Workspace dashboard.
- Added a sidebar Workspace link.
- Added a Clarise milestone setup flow with start, discussion, requirements, plan, decisions, and approval states.
- Linked artifacts continue to open in the existing Markdown editor.

## Tests Added

- Backend tests for collision-safe milestone start.
- Backend tests for discussion creation and answer preservation.
- Backend tests for requirements and plan generation.
- Backend tests for linked decisions.
- Backend tests for approval requirements and approval section idempotence.
- Backend tests for unsafe milestone ids.

## Validation Commands

- `cd services/symphonia_service && mix test` passed: 61 tests, 0 failures.
- `./node_modules/.bin/tsc --noEmit --pretty false` passed.
- `npm run build` passed.
- `git diff --check` passed.

## Smoke Checks

- Service `GET /healthz` returned 200.
- Temporary repository `SM9` was registered in an isolated registry.
- Spec workspace initialized.
- `milestone-001` was created through the service.
- Approval was blocked before required artifacts existed.
- Discussion saved user answers.
- Requirements artifact was generated.
- Plan artifact was generated.
- Decision was linked to the milestone.
- Milestone approval succeeded after required artifacts existed.
- Next.js proxy loop created and approved `milestone-002`.
- Linked plan artifact editor route returned 200.
- Task board route returned 200.

## Known Limitations

- Clarise generation is deterministic and template-based.
- Approved plans do not become tasks yet.
- No GitHub or Linear projection was added.
- No Coding Assistant run is started from an approved plan.
