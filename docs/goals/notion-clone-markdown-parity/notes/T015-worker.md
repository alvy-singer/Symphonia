# T015 Worker Receipt

Status: done

Objective:
- Complete final browser/runtime proof for create/list/edit/slash/publish/reload/delete/trash/permanent-cleanup on the disposable markdown page.

Proof completed:
- Reloaded `http://[::1]:3010/r/sym/docs/page-001`.
- Confirmed persisted state after reload:
  - URL remained `/r/sym/docs/page-001`.
  - title: `Codex parity proof after layout fix`
  - body contained `## Retest section` and the proof sentence.
  - sidebar contained the proof title.
  - editor showed `Published`.
- Opened ellipsis and confirmed `Delete` was visible.
- Clicked `Delete`; route returned to `/r/sym/docs`.
- Confirmed the proof title left the active docs list.
- Opened Trash and confirmed:
  - proof title visible in Trash
  - `Restore` visible
  - `Delete forever` visible
- Clicked `Delete forever`; Trash became empty and the proof title disappeared.

Failure found:
- Immediately after browser `Delete forever`, the pages API unexpectedly showed a fresh active `Untitled` `page-001` with no proof body.
- This means cleanup was not fully proven through the browser path, even though the proof-title page disappeared from Trash.

Cleanup:
- Deleted the leftover `page-001` through the local pages API.
- Confirmed `GET /api/repositories/SYM/pages?includeArchived=true` returned no pages.

Next required fix:
- Harden Trash action clicks so permanent delete cannot fall through or re-trigger the sidebar create affordance, then rerun the cleanup proof.
