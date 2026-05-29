# T017 Worker Receipt

Status: done

Objective:
- Apply the same immediate Untitled sidebar-create behavior from generic pages to existing workspace document collections such as milestones, requirements, plans, discussions, task proposals, task briefs, and decisions.

Files changed:
- `services/symphonia_service/lib/symphonia_service/spec_workspace.ex`
- `services/symphonia_service/lib/symphonia_service/http_server.ex`
- `app/api/repositories/[repoKey]/spec-workspace/artifacts/[artifactType]/route.ts`
- `components/sidebar/doc-tree.tsx`

What changed:
- Added a generic repo-backed spec artifact create route:
  - `POST /api/repositories/:repo/spec-workspace/artifacts/:type`
- Added a thin Next proxy for that generic create route.
- Added sidebar create controls for workspace collections:
  - Milestone group: Milestone, Discussion, Requirement, Task proposal, Task brief
  - Plans group: Plan
  - Decisions group: Decision
- Creating a workspace document starts as `Untitled`, refreshes the sidebar, and routes directly into the existing workspace editor.

Verification:
- `mix format lib/symphonia_service/spec_workspace.ex lib/symphonia_service/http_server.ex` -> passed.
- `npm run build` -> passed after network access was allowed for the required Google font fetch.
- `git diff --check` -> passed.
- Browser/API proof:
  - Opened `http://[::1]:3010/r/sym/docs`.
  - Confirmed sidebar contained the workspace create affordances including `New Plan`.
  - Clicked `New Plan`.
  - Browser routed to `/r/sym/workspace/plan/plan-003`.
  - Editor showed an `Untitled` workspace document.
  - API read confirmed `plan-003` existed as a repo-backed `plan` artifact with title `Untitled`.
  - Removed the disposable proof file `symphonia/plans/plan-003.md`.
  - API list confirmed only the original `plan-001` and `plan-002` remain.

Notes:
- Codebase singleton documents remain non-creatable, by design.
- This does not add Trash/permanent delete semantics for spec artifacts; it applies the immediate Untitled create-and-route behavior the user requested.
