# T014 Worker Receipt

Status: done

Objective:
- Fix the no-cover editor layout so saved-doc Publish and ellipsis actions are fully visible and clickable, then rerun focused verification for those actions.

Files changed:
- `components/editor/markdown-editor.tsx`

What changed:
- The editor affordance/action row now uses negative overlap only when a cover exists.
- No-cover pages now get normal top spacing, so `Publish` and ellipsis are no longer clipped at the top edge.

Verification:
- `npm run build` -> passed.
- `git diff --check` -> passed.
- Browser retest on `http://[::1]:3010/r/sym/docs/page-001`:
  - New no-cover proof page placed `Publish` at `y: 36.75` instead of `y: 0.75`.
  - Clicking `Publish` changed the DOM from `Publish` to `Published`.
  - Clicking ellipsis opened a visible `Delete` action.
  - API read showed `isPublished: true` for `page-001`.

Notes:
- A clean dev-server restart was required after `next build` caused a stale `.next` chunk error in the running dev server.
- The proof page remains temporary and should be cleaned up during final proof.
