status: accepted

# Documentation tree by role, not by name

## Context and problem statement
Every project names its documentation directories differently, and a tool that hardcodes names
cannot check any of them. The house this plugin comes from uses Portuguese names; the defaults
here are English. Dated file names must not collide between parallel agent sessions.

## Considered options
1. Fixed directory names — simple, breaks on the first project that already has a tree.
2. Roles declared in `.roadworthy/docs.json`, defaults for the missing ones — one indirection,
   every project keeps its names.
3. Sequential numbers (`NNNN-title.md`, MADR default) — collide when two sessions write at once.

## Decision
Option 2, with dated names `YYYY-MM-DD-HHMM-title.md`: sorted by name they are chronological,
and two sessions never produce the same name. MADR allows the variation ("numbers … unique
locally within a category").

## Consequences
- Good: `docs-check.sh`, `close-front.sh` and `resume-pick.sh` work on any tree.
- Bad: one more file to create; `docs-init.sh` creates it and never overwrites it.

## Confirmation
`bash tests/run.sh` section "docs-init.sh" (idempotency) and "docs-check.sh (roles)" pass;
`docs-check.sh docs/` passes on this repository's own tree.
