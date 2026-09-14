status: accepted

# Handoff — the suite becomes cases and fixtures — 2026-09-14 11:29

> Read this first. Every number below was measured in the act.

## State (measured now)

| Repository | Branch | HEAD | Tree | Version | Unpushed |
|---|---|---|---|---|---|
| `roadworthy` (this repository) | `main` | `780aa9a3d9b5` | dirty (this front, uncommitted) | 0.6.0 (manifests, unpublished) | 25 commits |

| gate | result |
|---|---|
| `bash tests/run.sh` | 29 cases, 359 assertions, `RESULT: gate clean`, 185 s |
| `bash tests/attack.sh` | 37 attacks, 32 refused, 5 declared |
| `docs-check.sh docs` | OK |
| `refute-ledger.sh hooks --sources …` | 8 fences, 0 without a record |
| `pointers-check.sh README.md` | OK |
| `claude plugin validate . --strict` | OK |

## What changed, and the measurement behind each

- **One case per fence and per script.** `tests/run.sh` was 1407 lines and 36 sections in one
  shell; it is now a runner over `tests/cases.txt`, with cases in `tests/hooks/`, `tests/scripts/`
  and `tests/meta/`, and the toy repositories in `tests/fixtures/`. The reason is a number, not
  taste: a refutation runs its check twice, so against the monolith it cost two full suite runs —
  the six refutations of `plan-preflight.sh` took 32 minutes. Against one case, **5.3 s**.
- **`tests/fixtures/` and `tests/hooks/` existed and were empty since 2 September**, untracked
  (git does not version an empty directory), cited by nothing. They now hold files, so a clone
  receives them.
- **Eight variables crossed section boundaries** — `PROJ`, `G`, `P`, `DI`, `CF`, `ON`, `SUB` and an
  exported `ROADWORTHY_DATA` still live six hundred lines after its section. Each is a fixture now.
  Proved by running every case alone under `set -u`, which is how they were found.
- **The defect the reorganisation exposed, and it is the heavy one:** the suite reported success on
  a suite that had died. `trap 'rm -rf "$TMP"' EXIT` makes an aborted script exit **0**, and
  carrying `$?` out does not help either — on bash 3.2 an unbound variable under `set -u` leaves
  `$?=0` in the handler, while an ordinary `set -e` failure leaves 1. `rw_end` sets a flag; no flag,
  no pass. `tests/meta/runner.sh` measures it in both directions, discriminator included.
- **`tests/cases.txt` is a fence, not a list.** A runner that globs loses a case the day the file
  is deleted. Refuted: with the comparison disabled, the self-test goes red naming the file.

## Where the real state lives

- `<plans_dir>/2026-09-14-1029-suite-em-casos-e-fixtures.md` — the approved plan of this front.
- `.roadworthy/plan.snapshot` — what was approved, and the base the closing measures against.
- `.roadworthy/refutations.jsonl` — including the two written today against the runner itself.
- `CHANGELOG.md` — the `[0.6.0]` entry now carries both sections dated 2026-09-14.

## Scoreboard — what this front got wrong on the way

| class | what it was |
|---|---|
| Trusting a mechanism instead of measuring it | wrote a parallel limiter around `wait -n`, which does not exist in the bash macOS ships (3.2); the limiter limited nothing while its comment said it did |
| Reading a measurement as proof of the thing next to it | the first standalone run showed 26 of 28 cases green; they were green because the harness was swallowing the abort, and four of them had died halfway |
| Editing by anchor without re-reading the file | the `--check-manifest` patch silently did not apply, and the self-test it was written for then called the whole suite, which called the self-test |

## What is NOT done

- **The seven-step bench of 0.5.0 is still empty**, and still the blocker for publishing. It runs
  only against an installed copy, and installing 0.6.0 means publishing — which is yours.
- **The fences guarding this session are still the installed 0.5.0**, not this code.

## Next concrete step

Publish, then run the bench against the installed 0.6.0 and fill the seven rows.

## Prompt to paste

```
Roadworthy: the suite is cases and fixtures now, gate clean, nothing unpushed pending except my
decision to publish. Read docs/plans/2026-09-14-1129-handoff-suite-em-casos-e-fixtures.md first, then the two 2026-09-14 sections of
CHANGELOG.md. The open item is mine: publish so the 0.5.0 bench can finally run.
```
