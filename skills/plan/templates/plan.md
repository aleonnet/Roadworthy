# <Title>

status: proposed

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
```
path/to/file
dir/**
```

## Acceptance (EARS)
| # | WHEN | THE SYSTEM SHALL | proved by | fails when |
|---|------|------------------|-----------|------------|
| 1 | `<condition>` | `<behaviour>` | `<command>` | `<output that means failure>` |

## Verification (after the last commit)
- `<gate command>` → expected result

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
