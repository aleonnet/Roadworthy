# <Title>

project: <absolute path of the repository this plan belongs to>
base: <git ref this plan is written against — omit when it is the working tree>
status: proposed
<!-- status: use the word your project declares under "status" in .roadworthy/docs.json.
     Left in English here because this template is copied by hand, with no script to fill it;
     docs-check.sh will tell you if the word is wrong for your project. -->

`project:` binds the plan to its repository: the plans directory is shared by every project,
and without it the gate can elect a newer plan of another project. `base:` is for a front that
branches from a tag or a release branch instead of the tip: declare it and every reading —
yours and the reviewer's — is done with `git show <base>:<path>` and `git grep <pattern> <base>`
instead of the working tree, so the review does not report divergences that only exist against
HEAD. The gate refuses a base that does not resolve, and refuses a review that declares a
different base from the plan's.

## Context
Why this change, what prompted it, the intended outcome.

## Risk band
One of: **protected** (report only, never edit — `protect-paths`), **critical** (end-to-end
diagnosis, refuted check, human bench), **standard** (refuted check, green suite, result
compared with the target), **minimal** (green suite). The band comes from the AREA touched, not
from the mood of the day.

## Impact sweep (commands run now)
```
<command>            # <what it measured>
<output>
```

## Changes, per file
- `path/to/file` — what changes and why. Reuse: `existing_function()` in `path`.

## Scope
The globs `scope-lock` will enforce, read from this fenced block by
`skills/plan/scripts/scope-write.sh` when the front opens.
```
path/to/file
dir/**
```

## Acceptance (EARS)
| # | WHEN | THE SYSTEM SHALL | proved by | fails when |
|---|------|------------------|-----------|------------|
| 1 | `<condition>` | `<behaviour>` | `<command>` | `<output that means failure>` |

## Verification (after the last commit)
Every line of the block below becomes one line of `.roadworthy/gates`, and `close.sh` runs each
with `bash -c`. So each line is a COMMAND -- never a bullet, never prose, never a placeholder.
Write what you expect underneath, outside the block.
```
<gate command>
<gate command>
```
Expected: `<what each one prints when it is green>`.

## Refutation
- `<check>` fails when `<defect>` — injection and expected failure text.

## Out of scope
- ...

## Overnight policy
Only read when the user orders unattended execution (`/roadworthy:overnight`); the skill refuses
a plan without this section.
- Decided at night, with a source: anything with an established answer — a primary document, a
  benchmark, the project's own canon — recorded in the diary and marked "ratify in the morning".
- Reserved for the user: anything irreversible, destructive or external (push, release, hardware
  writes, deletions), and these domains of this plan: `<list them, or "none">`.

## Open questions
- [NEEDS CLARIFICATION: ...]
