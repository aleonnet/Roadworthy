status: accepted

# Handoff — the rite inside plan mode — 2026-09-13 13:15

> Read this first. Everything below was measured in the act; no number here was carried over
> from another context.

## State (measured now)

| Repository | Branch | HEAD at the start | Tree | Version |
|---|---|---|---|---|
| roadworthy | `main` | `cd38ca6` | 15 files changed, uncommitted | 0.4.0 → 0.5.0 |

The scope lock of this front is in `.roadworthy/scope` (14 paths). It is released by
`/roadworthy:close` when the gates pass, never by hand.

## Where the real state lives

- `docs/decisions/2026-09-13-1301-the-rite-inside-plan-mode.md` — why the rite could not run
  inside plan mode, the options, the decision and its Confirmation.
- `CHANGELOG.md`, entry `[0.5.0]` — what changed, file by file, with the measurement behind each.
- `docs/reference/roadmap.md` — the field findings of 2026-09-08 still open, and the new section
  **Declared limits**: what we decided not to fix, with the reason.
- `.roadworthy/gates` — the three gate commands of this front. This repository had none, which
  is why its previous scope lock stood six days after that front shipped.

## What was delivered

**The rite fits in plan mode.** The plan file is exempt from the scope lock; the review may live
in a `## Review` section of the plan, which is the one file plan mode allows; the plan declares
`project:` and the gate elects by it instead of by modification time in a directory shared by
every project; a plan marked superseded is not a candidate, read with the vocabulary the project
declares in `.roadworthy/docs.json`; two live plans of one project are refused by name; a plan may
declare `base:` and the gate refuses a base that does not resolve or a review made against
another one.

**A closing cannot report success with nothing measured.** `close.sh --check` fails without a
gates file or with one that declares none; a run with zero gates keeps the scope and records
`gaps_found`; the night refuses to close on the same ground; the `plan` skill writes the gates
file in the same act as the scope; the scope-lock denial points at closing instead of widening.

## Acceptance, as approved (each line proved by a command)

| # | WHEN | THE SYSTEM SHALL | proved by |
|---|---|---|---|
| 1 | the lock is on and the write is the plan file | allow | `tests/run.sh`, scope-lock section |  |
| 2 | the lock is on and the write is another path outside the project | deny | same |  |
| 3 | the plan carries an approved review section and no sidecar | allow the submission | `tests/run.sh`, plan-mode section |  |
| 4 | that section carries no verdict | deny | same |  |
| 5 | a newer plan of another project sits in the shared directory | elect this project's | same |  |
| 6 | the elected plan belongs to another project | deny naming it | same |  |
| 7 | the closing runs with no gates file | fail | `tests/run.sh`, close section |  |
| 8 | the night closes with zero gates declared | refuse, keep the marker | `tests/run.sh`, overnight section |
| 9 | the whole rite runs inside plan mode | the plan reaches the approval screen with no gesture outside the mode | **NOT PROVED — see below** |
| 10 | the suite runs | `RESULT: gate clean` | `bash tests/run.sh` |

**Acceptance 9 is not proved, and it is the heart of this release.** This front submitted its own
plan with the gate *suspended* by the owner, because the gate blocked the repair of itself; and
every other proof here was made against this working tree with synthetic hook events, never
against the **installed** copy of the plugin in a real session — which is the copy a session
actually runs. Nothing in this release is claimed on that point. The bench below closes it, and
until it is filled the release is "proved by the suite, unproved in the field".

### Bench — fill the result column in a real session running 0.5.0

| # | step | expected result | a wrong result means | result (fill in the act) |
|---|---|---|---|---|
| 1 | `/plugin` after updating and `/reload-plugins` | version 0.5.0 | the update did not land |  |
| 2 | with a scope lock declared, write the plan file in plan mode | allowed | the plans-directory exemption did not ship |  |
| 3 | write a file outside the scope | denied, with the literal scope message | the lock loosened |  |
| 4 | submit a plan with no review section | denied, naming **this** plan and where to write the verdict | if it names another project's plan, the project binding did not ship |  |
| 5 | add `## Review` with `VERDICT: APPROVED` and submit | the plan reaches the approval screen | acceptance 9 fails: the rite still does not fit in the mode |  |
| 6 | declare a `base:` that does not exist and submit | denied, naming the ref | the base check did not ship |  |
| 7 | in a project with no `.roadworthy/gates`, run `close.sh --check` | fails | a closing can still report success with nothing measured |  |

Step 4 is only meaningful while the shared plans directory still holds plans of other projects —
101 of them when this was written.

## Proof

Twenty-four assertions added, every one exercised in both directions. Eleven guarantees refuted
with `skills/refute/scripts/refute.sh`: the defect injected, the check red for the intended
reason, green again on the clean file, the file restored with its hash verified, and zero
leftovers measured afterwards.

One defect was introduced and fixed during the work: an unpaired apostrophe inside the gate's
`$( … )` block breaks the hook with a syntax error far from the cause. Three such lines were
already in the file before this front. All are paired now, the block carries a note, and `bash
-n` in the suite is the mechanism that catches the class.

## Open limits

- The scope lock watches the edit tools, not the shell: a write through Bash is not guarded.
  Declared, with the reason, in `docs/reference/roadmap.md`.
- A changed plugin option does not reach a session that is already open; `/reload-plugins` or a
  new session applies it. Stated in `README.md`.
- A session runs the **installed** copy of the plugin, not this working tree: the fixes here take
  effect after a release and an update, or in a session that loads this directory.
- Two of the three items under Known in the changelog are the same vocabulary class fixed here,
  in files outside this front's scope. Reported, not changed in passing.

## Next concrete step

Run the gates on a clean tree and close:

```
bash tests/run.sh
bash skills/document/scripts/docs-check.sh docs
claude plugin validate . --strict
bash skills/close/scripts/close.sh
```

Then the owner decides on publishing, and on turning the plan-review gate back on: it was
suspended on 2026-09-13 because it blocked the repair of itself, and the repair is now in.
