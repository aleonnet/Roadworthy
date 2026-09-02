# <Title>

status: proposed

## Context
Why this change, what prompted it, the intended outcome.

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

## Open questions
- [NEEDS CLARIFICATION: ...]
