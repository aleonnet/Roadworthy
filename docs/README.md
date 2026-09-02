# Documentation map

Read this first. Each role below is a directory declared in `.roadworthy/docs.json`.

| Role | Where | What lives there |
|---|---|---|
| decisions | `docs/decisions/` | dated decision records (`YYYY-MM-DD-HHMM-title.md`, MADR status, Confirmation) |
| plans | `docs/plans/` | live fronts: plans and handoffs; the newest handoff by name is the current state |
| done | `docs/plans/done/` | concluded plans, each with a line in its `README.md` index |
| history | `docs/history/` | closed fronts, moved here by `close-front.sh` with citations rewritten |
| reference | `docs/reference/` | living canonical documents (undated names) |
| guides | `docs/guides/` | how-to guides and runbooks |
| archive | `docs/archive/` | excluded from checks, declared |

Resuming work: `/roadworthy:resume`. Checking the tree: `docs-check.sh`.
