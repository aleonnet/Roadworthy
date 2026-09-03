status: accepted

# Handoff — overnight {{topic}} — {{closed_iso}}

> Read this first. The state below was measured by `overnight-close.sh` at {{closed_iso}}.
> Nothing was pushed, bumped or released: those are yours to order.

## State (measured now)
| Repository | Branch | HEAD | Tree | Unpushed |
|---|---|---|---|---|
| {{repo}} | {{branch}} | {{head}} | {{tree}} | {{unpushed}} |

Gates: every declared gate FRESH on this tree (`close.sh --check`), evidence in
`.roadworthy/evidence.jsonl`.

## Where the real state lives
- `{{diary}}` — the decision diary: phase ledger, decisions with sources, blockers
- `{{plan}}` — the plan executed

## Blockers for the morning
{{blockers}}

## Bench (fill the result column on the real thing)
| step | action | expected result | result |
|---|---|---|---|
| 1 | | | |

## Prompts
- Passed: "The overnight delivery on {{topic}} passed the bench. Record it, then push."
- Failed: "The overnight delivery on {{topic}} failed at step <n>: <paste the literal error>."
