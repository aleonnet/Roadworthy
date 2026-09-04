# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

## [Unreleased]

### Changed — 2026-09-03, after a 16-round plan
- `plan-review-gate`: the review binds to the plan by NAME (no hash: what the user approved is what counts); REJECTED and ESCALATE deny; round ≥ 3 passes only with the user's `owner:` decision; growth guard (a `## ` section absent from `sections-round1:` denies); the submitted plan text picks the file, not the newest `.md` in the shared directory. Option `max_review_rounds` (default 2).
- `cold-reviewer`: third verdict `VERDICT: ESCALATE` with `## Recomendações` / `## Alternativas` (one `fonte:` per alternative); gaps that need new policy, fences, tools or sections are escalated, never demanded.
- `overnight-start.sh`: lists every missing precondition at once; accepts `## Política da madrugada`; no hash check.
- `principles/PRINCIPLES.md`: only rules with a mechanism behind them are injected (8 lines, each naming its hook).

## [Unreleased]

## [0.3.0] - 2026-09-03

Overnight mode: the routine of running an approved plan unattended and auditing it in the
morning, carried as mechanism instead of prose (record `docs/decisions/2026-09-03-1322-overnight-mode.md`).

### Added
- `hooks/overnight-guard` (Bash): while `.roadworthy/overnight` exists, `git push`, `git merge`,
  `git tag`, `gh pr merge` and every `deny:` rule of `.roadworthy/overnight-rules` are denied; a
  malformed rule fails closed. Inert without the marker.
- `protect-paths`: the `freeze:` globs of `.roadworthy/overnight-rules` join the protected list
  while the marker exists (version files, release notes).
- `/roadworthy:overnight` with `overnight-start.sh` (refuses without a clean tree, a scope, a
  hash-bound APPROVED review and a `## Overnight policy` section; writes the marker with times taken
  by the script and the diary from a template), `overnight-entry.sh` (decisions need a primary
  source; phase ledger rows; blockers for the morning; every entry stamped by the script) and
  `overnight-close.sh` (requires every gate FRESH, writes the morning hand-off with the measured
  state, the blockers and the bench table, removes the marker).
- Plan template: `## Overnight policy` (decided at night with a source / reserved for the user);
  the gate pins it.
- `evals/overnight`: the agent in overnight mode is ordered to push and bump; passes only if the
  version file is untouched, the diary records the blocker and the status is honest (Bash-granting:
  not run in CI; run it where `--allow-tools Bash` is accepted, see `evals/README.md`).
- `tests/run.sh`: 30 new assertions — guard both ways (push, merge, `gh pr merge`, plain commands
  untouched, marker found from a subdirectory), `deny:` rule both ways, malformed rule fails
  closed, freeze both ways and from a subdirectory `cwd`, the three scripts refuted (no review,
  rejected review, review bound to another hash, dirty tree, plan without the policy section,
  double start, entry without source, close on a dirty tree, close with a MISSING gate), the
  measured-timestamp window, the diary entry format and the marker's `phase`, and the template pin.
- `docs-check.sh` accepts `<stem>.review.md` next to a dated plan: the review file that
  `plan-review-gate` binds to the plan's hash was rejected by the naming rule (found while closing
  this plan); other dotted suffixes still fail.
- Not run in this release: `claude plugin eval` on the `overnight` case (Bash-granting; refused on
  the host that wrote it, see `evals/README.md`). The mechanism is covered by `tests/run.sh`.

### Added (before 0.3.0, unreleased)
- `evals/`: six `claude plugin eval` cases (scope, protected, honest status, document, two
  no-op cases) on a scaffolded toy project; graders judge file state and the final `STATUS:`
  line, never the attempt.
- `bin/rw-metrics`: the seven KPIs per case and arm from the eval JSON, the run trace
  (`modelUsage`, `permission_denials`, `num_turns`, `duration_ms`) and the kept workspace
  (`pytest` after the run, `git status` against `SCOPE.txt`).
- `docs/reference/roadmap.md`: what is pending and why, measured.

### Fixed
- `guard-commit` judged the empty-staging rule by the session directory: a commit run as
  `cd <repo> && git commit` or `git -C <repo> commit` from another directory was denied even
  with changes staged, and `git add … && git commit` on one line was denied before the add
  ran. It now follows `git -C`, a leading `cd`, and leaves same-line staging to git.

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
