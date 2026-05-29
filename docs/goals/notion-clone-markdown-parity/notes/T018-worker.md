# T018 Worker Receipt

## Outcome

Removed the old `/r/:repo/docs` index surface while preserving individual document pages at `/r/:repo/docs/:pageId`.

## Changes

- Replaced `app/r/[repoKey]/docs/page.tsx` with a redirect to the repo shell.
- Updated saved-doc delete fallback navigation to return to `/r/:repo`.
- Updated sidebar archive fallback navigation to return to `/r/:repo`.

## Verification

- `npm run build` -> passed after rerunning with network access for the configured Google font.
- `git diff --check` -> passed.
- `curl -I http://localhost:3010/r/sym/docs` -> returned `307 Temporary Redirect` with `location: /r/sym`.
