# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

## [Unreleased]

## [0.2.1] - 2026-09-02

Adopting 0.2.0 on a real multi-language monorepo showed four places where the scripts
assumed English or one indexing style. Each is now a project setting or an option, with a
fence for the accepted and the rejected case.

### Added
- `docs-check.sh`: a project may declare its own words for the five MADR states under
  `"status"` in `.roadworthy/docs.json` (for example `{"accepted": "aceito", "superseded by":
  "superado por"}`). The mapping replaces the English words for that project; states left
  out keep English. `superseded by` targets are resolved with the declared phrase.
- `refute-ledger.sh --exclude <regex>`: a test whose first 6 lines match declares itself a
  diagnostic (dump, probe, spike), not a guarantee, and is skipped.

### Changed
- `docs-check.sh`: the concluded-plans index accepts links with a `./` prefix
  (`[x](./file.plan.md)`), and `--since` now also exempts handoffs dated before the cut from
  the live-handoff rule, in the same way it exempts them from the name rule.
- `tree-fingerprint.sh` excludes transient Roadworthy state (scope, state, ledgers) so that
  releasing the scope after a pass does not mark the evidence STALE.

## [0.2.0] - 2026-09-02

### Added
- Documentation tree by role (`.roadworthy/docs.json`): `docs-init.sh` (idempotent, never
  overwrites), role-aware `docs-check.sh` (concluded plans must be indexed; only the newest
  handoff by name may be live), `close-front.sh` (dry-run by default; `--apply` moves a closed
  front into history and rewrites every link).
- `close.sh`: gates declared in `.roadworthy/gates`, run only on a clean tree, each recorded in
  `evidence.jsonl` with the content fingerprint; `--check` reports FRESH / STALE / MISSING;
  states `passed | gaps_found | needs_human`; success releases the scope lock.
- `tree-fingerprint.sh` now follows content (`git write-tree` on a temporary index).
- `pointers-check.sh` (instruction files cite files that exist; memory index and files agree both
  ways) and `refute-ledger.sh` (a test that calls itself a fence carries its refutation record).
- `/roadworthy:resume` with `resume-pick.sh`: newest handoff by name, never by mtime; follows
  `superseded by` and fails on cycles.
- `protect-paths` also honours the project file `.roadworthy/protected`.
- `review_suffix` option; the review file also accepts Portuguese field names and verdicts.
- Principle 13 (speak in outcomes, never bare identifiers); risk band in the plan template.
- The plugin uses its own documentation tree (`docs/`, created by `docs-init.sh`).

## [0.1.1] - 2026-09-02

### Changed
- Guards (`scope-lock`, `protect-paths`, `guard-commit`, `plan-review-gate`) now **fail closed**:
  an internal error or malformed event denies the action. `principles` keeps failing open with a
  notice. The policy is declared per hook (`RW_ON_CRASH`) and a hook without one is itself an
  error; all three paths are covered by `tests/run.sh`.
- `refute.sh` also proves the check is **green on the clean file** after the restore; red on
  both sides is reported as "does not measure the defect".
- README states the measured context cost.

## [0.1.0] - 2026-09-02

### Added
- Hooks: `principles` (UserPromptSubmit), `scope-lock` and `protect-paths` (Edit/Write),
  `guard-commit` (Bash), `plan-review-gate` (ExitPlanMode). All fail open on internal error
  (exit 1 + notice) and use exit 2 only for deliberate denials.
- Skills: `plan`, `refute`, `close`, `document`, with `refute.sh`, `tree-fingerprint.sh`
  and `docs-check.sh`.
- Agent: `cold-reviewer` (read-only, fails closed, correctness-only findings).
- User configuration via `plugin.json` `userConfig`; self-hosted marketplace for a
  two-command install.
- `tests/run.sh`: hooks exercised in both directions with real stdin JSON, scripts refuted,
  manifests validated, privacy scan; CI on macOS and Linux.
