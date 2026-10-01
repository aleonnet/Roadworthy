status: superado por 2026-09-14-1129-handoff-suite-em-casos-e-fixtures.md

# Handoff — 0.6.0, the rite stops being optional — 2026-09-14 03:31

> Read this first. Every number below was measured in the act; none was carried over from
> another context.

## State (measured now)

| Repository | Branch | HEAD | Tree | Version | Unpushed |
|---|---|---|---|---|---|
| `roadworthy` (this repository) | `main` | `d31312f0fc91` | clean | 0.6.0 (manifests) | 23 commits |

Suite: 318 assertions, `RESULT: gate clean`. Attack suite: 37 attacks, 32 refused, 5 declared. Refutations recorded by the script in `.roadworthy/refutations.jsonl`: 23 of this repository's own files, across 10 of them (the ledger also holds the toy refutations every suite run makes, which are not these).

## Where the real state lives
- `<plans_dir>/leia-as-diretrizes-do-quiet-hopcroft.md` — the approved plan, 54 defects each
  with an explicit destination, 63 acceptance rows, and the reading counter that took seven rounds.
- `.roadworthy/plan.snapshot` — what was approved: the plan, the base HEAD, the globs, the gates
  and the three digests the closing measures against.
- `.roadworthy/refutations.jsonl` — every refutation with both hashes and both exit codes, written
  by `refute.sh`, never by the agent.
- `.roadworthy/denials.jsonl` — every denial with the fence, the reason and the front.
- `CHANGELOG.md` `[0.6.0]` — the release in prose, including the five behaviour changes.
- `docs/decisions/2026-09-14-0239-four-accepted-claims-refuted.md` — the four accepted records that did not survive a whole reading.

## Read first, in this order
1. `CHANGELOG.md`, the `[0.6.0]` entry — the five behaviour changes are what breaks on upgrade.
2. `docs/reference/roadmap.md`, **Pending — named in the 0.6.0 reading** and **Declared limits**.
3. This file's scoreboard, below.
4. `docs/plans/2026-09-13-1315-handoff-the-rite-inside-plan-mode.md` — the 0.5.0 bench, which is
   the one thing 0.6.0 does not close.

## What is NOT done, and why

- **The seven-step bench of 0.5.0 is still empty.** It must be run in a real session against the
  **installed** copy, and installing 0.6.0 means publishing, which is the owner's act. The result
  column now exists (it did not; acceptance 53 was checking a column that was not there, which
  passes on emptiness — the shape of every false green). This is the blocker for publishing.
- **`hooks/scope-ledger` was not built**, deliberately. It would make visible an act that is now
  prevented; the reason is in the roadmap where the pending line was.
- **The four eval graders (defects 51–54) were not touched.** `claude plugin eval --allow-tools
  Bash` is refused on this machine by the Docker credential defect, so any fix would be written
  and never measured.
- **The fences that guarded this session were 0.5.0, not this code.** Measured at 03:30: the two
  real denials of the day left no row in `.roadworthy/denials.jsonl`, and firing the same denial
  against the working tree writes one immediately. The ledger is a 0.6.0 mechanism and the session
  runs the **installed** copy. Everything in this release is proved by the suite and by the attack
  suite against this tree; nothing here is proved in the field. That is the same gap 0.5.0 left,
  and it is why the bench above is the blocker rather than a formality.
- **The plan was edited after approval, twice, and both are written down.** `scope-ledger` came out
  of the Verification block (it will never exist, so that gate could never pass), and
  `tests/goldens/**` was added to the Scope after the closing refused the front and named three
  files written outside it. The second is the mechanism catching me: the goldens were the same
  deliverable, in a directory the scope did not name.

## Scoreboard — what this front got wrong on the way

| class | what it was | defect |
|---|---|---|
| Diagnosing by matched pattern instead of an open file | five review rounds on a plan built from search; the whole-file reading found 54 defects where search had found 14, and the four worst were on the line AFTER the match | the root of all below |
| Taking an accepted record as a measurement | wrote that `ExitPlanMode` carries no plan text because a decision record said so; my own submission refuted it | 14 |
| Marking as an unfixable limit what I did not want to fix | `run-hook.cmd` exiting 0 without bash, called "not fixable here" — it was an `echo` and an `exit /b`, in a file inside my scope | 11 |
| Writing a mechanism's reason without running it | claimed the refutation catalogue matched two hooks by name; measured `0 fence(s)` | 20 |
| Changing an option's contract without reading its declared type | nearly turned `plan_review_required` into a string read by `rw_bool`, which would have made the whole gate exit 0 in silence | — |
| Narrating a correction instead of making it | three corrections declared and not made, which is why the declared-correction form is now machine-checked | 26 |
| Stale numbers inside my own document | a pre-flight block claiming 56 acceptance rows when the plan had 61 | — |
| Citing by bare filename | the same defect the front was fixing in `rw_glob_match`, committed in the plan's own citations | 5 |
| Writing an assertion that asks "did it deny?" and not "why?" | five weak assertions found by refutation, each passing for a reason that had nothing to do with the guarantee | — |
| Letting my own test fixtures pollute the front | refusal-test plans written inside the front's repository counted as stray files — caught by the check I had just written | 18 |
| Believing my own comment over a measurement | wrote that `head -N` counted as a whole reading; measured, it only matched with two spaces, so the branch fired on a typo | — |
| An instrument that judged against the wrong state | the pre-flight read the working tree, so every correction made during the front turned the plan's own citations into false alarms | — |

## Next concrete step

The front is **closed**: `close: passed`, all six gates OK on tree `226cab6af3d6a48a`, evidence in
`.roadworthy/evidence.jsonl`, scope released and reopened only to write this file.

| gate | result |
|---|---|
| `bash tests/run.sh` | OK — 318 assertions, `RESULT: gate clean` |
| `bash tests/attack.sh` | OK — 37 attacks, 32 refused, 5 declared |
| `bash skills/document/scripts/docs-check.sh docs` | OK |
| `bash skills/refute/scripts/refute-ledger.sh hooks --sources …` | OK — 8 fences, 0 without a record |
| `bash skills/document/scripts/pointers-check.sh README.md --root .` | OK |
| `claude plugin validate . --strict` | OK |

What is left is yours: **publish**, so the bench can finally run against an installed 0.6.0, and
then fill the seven rows. Until that happens this release is in exactly the position 0.5.0 was in —
proved by the suite, unproved in the field — and it says so out loud rather than shipping quietly.

## Prompt to paste

```
Roadworthy 0.6.0 is committed, suite and attack suite green, version bumped in both manifests.
Read docs/plans/2026-09-14-0331-handoff-the-rite-stops-being-optional.md first, then the [0.6.0] entry of CHANGELOG.md.
Two things are open and both are mine to decide: the gates line that still names scope-ledger,
and whether to publish so the 0.5.0 bench can finally be run against the installed copy.
```
