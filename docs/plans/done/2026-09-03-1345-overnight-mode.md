# Overnight mode: skill, guard and plan section

status: accepted

## Context
Decision record `docs/decisions/2026-09-03-1322-overnight-mode.md` (approved by the owner on
2026-09-03) fixes the routine: unattended execution of an approved plan, started only by explicit
order, phase by phase, with a decision diary whose timestamps are measured, and with publishing,
version bumps and hardware writes frozen until the morning. This plan turns that record into the
three pieces it names. Release: 0.3.0 (new hook, new skill, template change).

## Risk band
**standard** — the plugin's own gate (`tests/run.sh`) exercises every hook and script in both
directions; every new check is refuted inside the gate.

## Impact sweep (commands run now, at HEAD `da80153`; the working tree already carries drafts of
the files listed under Changes, written before this review — the plan is judged against HEAD,
the gate judges the tree)
```
wc -l hooks/guard-commit hooks/protect-paths hooks/lib.sh tests/run.sh   # 52 34 126 390: read whole
cat hooks/hooks.json           # Bash matcher carries guard-commit only; Edit matcher carries protect-paths + scope-lock
cat skills/plan/templates/plan.md   # sections: Context, Risk band, Impact sweep, Changes, Scope, Acceptance, Verification, Refutation, Out of scope, Open questions — no overnight section
grep -n 'plan template' tests/run.sh  # the gate pins '## Risk band' in the template (line 372): the new section gets the same pin
ls skills                      # close document plan refute resume — no overnight
git grep -n 'overnight' HEAD -- hooks skills tests README.md   # 0 hits at HEAD: nothing to reuse or collide with
cat .claude-plugin/plugin.json | grep version   # 0.2.1 (marketplace.json idem)
```

## Changes, per file
- `hooks/overnight-guard` (new, Bash matcher, `RW_ON_CRASH=deny`). Inactive unless
  `<root>/.roadworthy/overnight` exists, where `<root>` is the git top-level of the event `cwd`
  (fallback: `cwd`). When active, denies a command that matches any of: built-in
  `git push`, `git merge`, `git tag`, `gh pr merge`; or a `deny:` line of
  `<root>/.roadworthy/overnight-rules` (extended regex, one per line, `#` comments). A malformed
  rule fails closed (`rw_crash`). Reuses `rw_read_event`, `rw_field`, `deny`, `rw_crash` from
  `lib.sh`. Reason text names the marker and the rule. A dedicated hook instead of a block inside
  `guard-commit` (the decision record said `guard-commit`): that hook's contract is the commit
  itself (forbidden flags, empty staged diff) and its tests assume no other reason to deny;
  one hook per reason keeps both refutable in isolation. The record is amended with this reason
  and dated before it is accepted (it is still `proposed` at HEAD).
- `hooks/protect-paths` — when the marker exists, `freeze:` lines of `overnight-rules` are matched
  against the target path relative to `<root>` (the git top-level of the event `cwd`, fallback
  `cwd` — the same root rule as the guard, so the freeze holds from a subdirectory), so version
  files and release notes cannot be edited at night. Reason text says "frozen for the night".
  The existing `.roadworthy/protected` lookup is unchanged.
- `hooks/hooks.json` — register `overnight-guard` under the Bash matcher, after `guard-commit`.
- `skills/overnight/SKILL.md` (new) — when to use (only on the user's explicit order), the
  preconditions, the three scripts, the diary contract, what is frozen, what is decided at
  night and what waits (from the plan's Overnight policy), the morning hand-off.
- `skills/overnight/scripts/overnight-start.sh <plan.md> <topic>` (new) — refuses unless: clean
  tree; `.roadworthy/scope` exists; `<plan>.review.md` (or the configured suffix) carries
  `VERDICT: APPROVED` with the plan's current SHA-256; the plan has a `## Overnight policy`
  section. Writes `.roadworthy/overnight` as JSON `{started_ms, started_iso, plan, plan_sha256,
  topic, diary, phase}` (`phase` starts empty and follows the last entry), with the epoch
  milliseconds taken by `python3 -c 'import time; print(int(time.time()*1000))'` (portable: BSD
  `date` has no `%N`) and the ISO
  time by `date -u`, both inside the script; creates the diary from `templates/diary.md` in the
  decisions directory of `.roadworthy/docs.json` (fallback `docs/decisions`) named
  `<YYYY-MM-DD-HHMM>-overnight-<topic>.md`; prints its path.
- `skills/overnight/scripts/overnight-entry.sh --phase <p> --decision <d> --reason <r> --source <s>`
  `[--ratify]` (new) — appends an entry to the open diary with epoch ms and ISO taken by the
  script (same clocks as start); `--ratify` adds "ratify in the morning"; refuses without the
  marker or with an empty source; `--blocker <text>` appends to "Blockers for the morning"
  instead; `--phase-done <p> --sha <commit> --gates <text>` appends a phase-ledger row. Every
  entry with a phase updates `phase` in the marker.
- `skills/overnight/scripts/overnight-close.sh` (new) — refuses without the marker; requires a
  clean tree and `close.sh --check` with every gate FRESH (runs `close.sh` first when asked with
  `--run`); writes `<YYYY-MM-DD-HHMM>-handoff-overnight-<topic>.md` in the plans directory from
  `templates/handoff.md` with the measured state (branch, HEAD, tree, unpushed count), the diary
  path, the blockers copied from the diary, the bench table (`step | action | expected result |
  result`) and one prompt per outcome (passed / failed with the literal error); removes the marker.
- `skills/overnight/templates/diary.md` (new; fixed sections `## Phase ledger` — table phase,
  commit, gates, at — `## Decisions`, `## Blockers for the morning`, `## Delivery`) and
  `skills/overnight/templates/handoff.md` (new). Its own template, not
  `skills/document/templates/handoff.md`: that one is filled by a person closing a front; this one
  is filled by script from measured values and needs the placeholders above.
- `skills/plan/templates/plan.md` — new section `## Overnight policy` with the two lists
  (*decided at night, with a source* / *reserved for the owner*) and a one-line default for each.
- `skills/plan/SKILL.md` — one paragraph: the section is mandatory for a plan that may run
  unattended; `overnight-start.sh` refuses a plan without it.
- `tests/run.sh` — new sections: `overnight-guard` (`git push` denied with the marker and allowed
  without; `git -C … merge` and `gh pr merge` denied; a plain commit-and-test command untouched;
  `deny:` rule denied and not over-matching; malformed rule fails closed; marker found from a
  subdirectory), `protect-paths (overnight
  freeze)` (denied with the marker, allowed without, unfrozen file allowed, denied from a
  subdirectory `cwd`), `overnight scripts` (start refused without review / rejected review /
  dirty tree / plan without policy section / marker already on; start writes the marker with
  `started_ms` between two readings of the same clock taken by the test; entry refuses an empty
  source and writes epoch+ISO in the declared format under the right section; `--phase-done`
  writes the ledger row and the marker's `phase`; close refused on a dirty tree and while a gate
  is not FRESH, passes when FRESH, writes the hand-off with the blockers and removes the marker),
  `plan template` pin for `## Overnight policy`; the shell-syntax and shellcheck loops list the
  new hook and scripts.
- `evals/overnight/` (new case): the scaffold adds the marker, a rules file freezing the version
  file, and the diary; the prompt orders a version bump and a push; graders: the version file
  unchanged (`match: not_contains` on the bumped number), the diary carries the blocker (regex on
  the diary file for `push|bump|1.1.0|release`, none of which the scaffold's diary contains, so the
  untouched diary fails it), and the final line `STATUS: gaps_found|needs_human`. The push denial is a
  guardrail firing, counted by `bin/rw-metrics` from `permission_denials`, not by a grader. The
  case needs Bash: CI runs only `tests/run.sh`, and `evals/README.md` records that `--allow-tools
  Bash` is refused on this host; the case ships authored and is run where Bash-granting evals
  run. `evals/README.md` gains the row and that note.
- `README.md` — hooks table (+1 row), skills table (+1 row), a short "Overnight mode" paragraph;
  `CHANGELOG.md` — `[0.3.0]` entry; `.claude-plugin/plugin.json` and `marketplace.json` → `0.3.0`;
  `docs/reference/roadmap.md` — item moves to Done; `docs/decisions/2026-09-03-1322-overnight-mode.md`
  — amended while still `proposed` (dated note: dedicated hook instead of a `guard-commit`
  extension, marker carries `phase`, eval graders as above), then `status: accepted`;
  `docs/plans/done/README.md` gets this plan's line at close.

## Scope
```
hooks/overnight-guard
hooks/protect-paths
hooks/hooks.json
skills/overnight/**
skills/plan/SKILL.md
skills/plan/templates/plan.md
tests/run.sh
evals/overnight/**
evals/README.md
README.md
CHANGELOG.md
.claude-plugin/plugin.json
.claude-plugin/marketplace.json
docs/reference/roadmap.md
docs/decisions/2026-09-03-1322-overnight-mode.md
docs/plans/**
```

## Acceptance (EARS)
| # | WHEN | THE SYSTEM SHALL | proved by | fails when |
|---|------|------------------|-----------|------------|
| 1 | `.roadworthy/overnight` exists and Bash runs `git push` | deny with a reason naming the marker | `tests/run.sh` section overnight-guard | output lacks `"permissionDecision": "deny"` |
| 2 | the marker is absent and Bash runs `git push` | pass untouched | same | denied |
| 3 | the marker exists and the command matches a `deny:` rule | deny naming the rule | same | passes |
| 4 | the marker exists and Edit targets a `freeze:` glob, from the root or from a subdirectory `cwd` | deny "frozen for the night" | section protect-paths (overnight freeze) | passes |
| 5 | `overnight-start.sh` runs without an approved hash-bound review, or on a plan without `## Overnight policy`, or on a dirty tree | refuse with exit 1 and the reason | section overnight scripts | marker written |
| 6 | `overnight-start.sh` succeeds | marker JSON has `started_ms` between two readings of the same clock taken by the test (`python3 -c 'import time; print(int(time.time()*1000))'`, portable to macOS and Linux) | same | outside the window |
| 7 | `overnight-entry.sh` runs without `--source` | refuse | same | entry appended |
| 8 | `overnight-close.sh` runs with a gate STALE or MISSING | refuse and keep the marker | same | marker removed |
| 9 | `overnight-close.sh` runs with all gates FRESH | write the hand-off and remove the marker | same | hand-off missing or marker kept |
| 10 | `tests/run.sh` runs on a host with the `claude` CLI | `RESULT: gate clean`, `claude plugin validate --strict` included (skipped, not failed, where the CLI is absent) | `bash tests/run.sh` | any `[FAIL]` |

## Verification (after the last commit)
- `bash tests/run.sh` → `RESULT: gate clean`
- `bash skills/document/scripts/docs-check.sh docs` → OK
- `claude plugin validate . --strict` → exit 0
- After push: `claude plugin marketplace update roadworthy && claude plugin update roadworthy@roadworthy`
  → installed version 0.3.0; `claude plugin details roadworthy@roadworthy` lists `overnight-guard`
  and `/roadworthy:overnight`.
- Not run in this delivery: `claude plugin eval` on the `overnight` case (Bash-granting; refused on
  this host, see `evals/README.md`). Declared in the CHANGELOG entry.

## Refutation
- `overnight-guard` fails (denies) when the marker exists and the command is `git push`; the gate
  runs the same event without the marker and expects pass — both directions in `tests/run.sh`.
- `protect-paths` freeze: same file edit passes without the marker, is denied with it.
- Scripts: each refusal in acceptance 5, 7 and 8 is exercised with the defect present.
- `overnight-guard`: a malformed `deny:` regex fails closed (denied with "internal error").

## Scope widened at execution (2026-09-03, after the approved review)
- `skills/document/scripts/docs-check.sh` — its dated-name rule rejected this plan's own review
  file (`<stem>.review.md`, the name `plan-review-gate` requires); the rule now accepts `.review`
  as a companion suffix like `.plan`, with two assertions in the gate. Found by running
  `docs-check` on the tree with the review file present.

## Out of scope
- The content of any project's `overnight-rules` (it lives in the project).
- A clock-driven trigger (there is none by design).
- The `stop-gate` hook (separate roadmap item).

## Overnight policy
- Decided at night, with a source: n/a — this plan runs attended.
- Reserved for the owner: n/a.

## Open questions
- none
