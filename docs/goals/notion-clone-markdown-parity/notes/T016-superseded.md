# T016 Superseded

The Trash restore/delete-forever cleanup task is no longer valid.

The user explicitly clarified that this behavior was deleted on purpose and must not be reintroduced. The attempted reintroduction was reverted, and `components/sidebar/doc-tree.tsx` no longer contains the Trash, Restore, Delete forever, or related archived-page controls.

Verification:

- `rg "Trash|Restore|Delete forever|RotateCcw|Trash2|archivedPages|onRestore|onPermanentDelete|archivedForRepo|deletePage|restorePage" components/sidebar/doc-tree.tsx -n` -> no matches.
- `npm run build` -> passed.
