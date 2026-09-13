# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

## [Unreleased]

### Known — 2026-09-07, measured on the first full overnight → close → merge cycle
- `overnight-close.sh` writes `status: accepted` in the hand-off it generates, ignoring the project's `status` vocabulary in `.roadworthy/docs.json`; on a project declaring Portuguese words `docs-check` rejects the file the plugin itself wrote (fixed by hand on the project; to fix here: read the vocabulary like `docs-check.sh` does).
- `resume-pick.sh` follows only the English `status: superseded by <file>` line; on a project that declares its own words in `.roadworthy/docs.json` (`"superseded by": "superado por"`) it returns the SUPERSEDED hand-off (measured 2026-09-07: the newest file by name was `…-1215-handoff-overnight-…`, marked `superado por …-0056-…`, and the script printed the 1215 file). To fix here: read the vocabulary the way `docs-check.sh` does before matching the status line.
- `overnight-guard` finds the marker by walking up from the session's cwd, not from the repository the command targets: `cd <other-repo> && git push` run from inside a project in overnight mode was denied although the other repository had no marker (workaround: run from a directory outside the marked project; to fix here: resolve the marker from the `-C`/`cd` target the way `guard-commit` already does).

The first two are the same class of defect that 0.5.0 fixed in `plan-review-gate`: read the
project's state vocabulary from `.roadworthy/docs.json`, one dictionary for the whole house.
`resume-pick.sh` and the hand-off writer were outside the approved scope of that front, so they
stay reported here rather than changed in passing.


## [0.5.0] - 2026-09-13

The plan rite could not be executed in the mode the plugin tells the agent to use. Two sessions,
in two projects, hit it on the same day; both escaped by hand, and one lost a ten-minute review
because the verdict had nowhere to go. This release makes the rite fit in plan mode, binds a plan
to its project and its base, and stops a closing from reporting success with nothing measured.

**What is proved and what is not.** Every change here is covered by the suite in both directions
and refuted once (defect injected, expected failure text, file restored by hash). What is *not*
proved is the end-to-end path: this front submitted its own plan with the gate suspended, because
the gate blocked the repair of itself, and every hook was exercised with synthetic events against
this working tree — never against the installed copy in a real session. The bench that closes
this is in `docs/plans/2026-09-13-1315-handoff-the-rite-inside-plan-mode.md`.

**Behaviour change to know about before upgrading:** `close.sh --check` now fails in a project
with no `.roadworthy/gates`, where it used to print the absence and exit 0. That is the fix, and
it will surface in projects that never declared gates.

### Fixed — 2026-09-13, the rite was impossible inside plan mode
The plan rite asked for three files — the plan, the scope lock and the review — and plan mode
lets an agent write one. Two sessions in two projects hit it on the same day; both escaped by
widening the scope by hand or by leaving the mode, and one lost a ten-minute review with twelve
blockers because the verdict could not be written anywhere. The contradiction was in the plugin,
not in the models following it.
- `scope-lock`: the plan file is exempt. Its own comment already promised that the plan's
  artefacts are always editable, but the exemption covered only `.roadworthy/`; the plan lives in
  `plans_dir`, outside the project, so it was compared as an absolute path and denied. Paths are
  resolved through symlinks on both sides before matching.
- `plan-review-gate`: the review may live in a `## Review` (`## Banca`) section of the plan
  itself, which is what plan mode allows; the sidecar `<plan><review_suffix>` keeps working and
  takes precedence. The review's own heading never counts as growth, so a plan that already had
  round 1 can adopt the new form without tripping the growth guard.
- `plan-review-gate`: the plans directory is shared by every project (101 plans of several
  projects in one directory, measured), and the gate elected another project's plan and denied
  with a cryptic "no review". A plan now declares `project:` in its header and the gate elects by
  that; a plan of another project is named in the denial. Comparison resolves symlinks (`/var`
  and `/private/var` named one directory as two on macOS).
- `plan-review-gate`: a plan marked superseded in its header is not a candidate, read with the
  words the project declares under `status` in `.roadworthy/docs.json` — the same vocabulary
  `docs-check.sh` reads, not a second dictionary. Two live plans of one project are refused with
  both names instead of resolved by date; a directory of older drafts that declare no project is
  left alone, so nobody is blocked on upgrade.
- `plan-review-gate`: a plan may declare `base:` when the front is written against a tag or a
  release branch instead of the tip. The gate refuses a base that does not resolve, and refuses a
  review that declares a different base from the plan's — which is what turns "remember to tell
  the reviewer which ref to read" into a mechanism. Undeclared, the base is the working tree and
  nothing changes.
- `skills/plan`: the scope lock is written as the first act of execution, not before the plan is
  approved; the review goes in the plan in plan mode; the reviewer runs in the background because
  the harness offers no foreground, and its verdict is written to disk the moment it arrives.
  Reading and reviewing follow the plan's `base:` when it declares one.
- Internal: an unpaired apostrophe in a comment inside the gate's `$( … )` block breaks the hook
  with a syntax error far from the cause — bash counts quotes while scanning a command
  substitution, heredoc included. Three such lines were already in the file. All paired, with a
  note at the block; `bash -n` in `tests/run.sh` is the mechanism that catches it.
- `tests/run.sh`: 20 assertions for the above, in both directions, and each guarantee refuted
  (defect injected, expected failure text, file restored with its hash verified).

### Fixed — 2026-09-13, a closing that measured nothing reported success
- `close.sh --check`: no `.roadworthy/gates`, or a file that declares none, now **fails**. It
  used to print the absence and exit 0, and `overnight-close.sh` reads that output looking for
  refusal words — so a project with no declared gate closed the night reporting every gate FRESH.
  Measured on this repository, which had no gates file at all; the consequence was a scope lock
  that nobody could release, still standing six days after its front shipped, which is what sends
  the next front to widen the scope by hand.
- `close.sh`: the same for a real run — with zero declared gates it fails, keeps the scope and
  records `gaps_found`, instead of writing `passed` and releasing the lock.
- `overnight-close.sh`: the refusal now names the missing declaration instead of speaking only of
  STALE and MISSING gates.
- `skills/plan`: the skill writes `.roadworthy/gates` from the plan's Verification section in the
  same act as the scope, so the file `close` requires exists from the start.
- `scope-lock`: the denial says what to do when the scope belongs to a front that already
  finished — close it, not widen it.

## [0.4.0] - 2026-09-07

### Fixed — 2026-09-07, measured on a project's first morning after an overnight
- `docs-check.sh`: the review the `plan` skill writes next to a plan is `<plan><review_suffix>` — for `x.plan.md` that is `x.plan.review.md`, carrying `plan:` / `round:` / `VERDICT:` and no `status:`. The name rule accepted `.plan.md` **or** `.review.md`, never both, and the status rule rejected every real review, so the gate the skill itself sets up was red by construction. Now `.plan.review.md` is a valid companion and a `.review.md` file must carry a `VERDICT:` line instead of a status.
- `pointers-check.sh`: a memory file linked only from a sub-index that `MEMORY.md` links to (an index split by theme) counted as an orphan — 51 false failures on one project. Reachability now follows markdown links from the index through the files it reaches inside the memory directory; a file nothing reaches still fails, and the text-stem citation in `MEMORY.md` still counts.

### Changed — 2026-09-03, after a 16-round plan
- `plan-review-gate`: the review binds to the plan by NAME (no hash: what the user approved is what counts); REJECTED and ESCALATE deny; round ≥ 3 passes only with the user's `owner:` decision; growth guard (a `## ` section absent from `sections-round1:` denies); the submitted plan text picks the file, not the newest `.md` in the shared directory. Option `max_review_rounds` (default 2).
- `cold-reviewer`: third verdict `VERDICT: ESCALATE` with `## Recomendações` / `## Alternativas` (one `fonte:` per alternative); gaps that need new policy, fences, tools or sections are escalated, never demanded.
- `overnight-start.sh`: lists every missing precondition at once; accepts `## Política da madrugada`; no hash check.
- `principles/PRINCIPLES.md`: only rules with a mechanism behind them are injected (8 lines, each naming its hook).

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
