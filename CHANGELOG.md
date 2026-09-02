# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

## [Unreleased]

### Planned for 0.2
- Documentation tree by role (`.roadworthy/docs.json`): `docs-init.sh` (idempotent), role-aware
  `docs-check.sh` (done index, superseded handoffs), `close-front.sh` (move to history with
  citation sweep).
- `close.sh`: declared gates in `.roadworthy/gates`, run after the last commit, evidence with tree
  fingerprint; verification states `passed | gaps_found | needs_human`.
- `pointers-check.sh` (instruction files and memory index point at files that exist, both ways)
  and `refute-ledger.sh` (tests marked as fences carry a refutation record).
- `/roadworthy:resume`: read the map, find the newest handoff by name, state what was read.
- Principle 13: speak in outcomes, never bare identifiers. Risk-band field in the plan template.
  Configurable review-file suffix.

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
