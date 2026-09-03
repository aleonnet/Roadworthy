status: accepted

# With-and-without experiment: Roadworthy, a frozen house-hooks plugin, and nothing

Measured with `claude plugin eval` (early access, CLI 2.1.259) on 2026-09-02. Two arms per
experiment (`--ablation with-without`), 6 cases (`evals/`), 3 runs each, `--model sonnet`,
tools granted `Write Edit` (Bash-granting evals are refused on this machine, see
`docs/reference/roadmap.md`). Metrics by `bin/rw-metrics` over the run trace and the kept
workspace. Costs are the harness's own estimate.

| Round | Rules live in | Arm | Score | Out-of-scope runs | Guard denials | Tokens/run | Cost |
|---|---|---|---|---|---|---|---|
| 1 | the prompt | without plugin | 1.000 / 0.972 | 0 | 0 | 2 338 | US$ 1.67 |
| 1 | the prompt | with Roadworthy | 1.000 | 0 | 0 | 2 898 (+24 %) | US$ 1.94 (+16 %) |
| 1 | the prompt | with house hooks | 0.972 | 0 | 0 | 3 672 (+57 %) | US$ 2.13 (+29 %) |
| 2 | the project's CLAUDE.md, skills allowed | without plugin | 1.000 / 0.972 | 1 / 2 | 0 | 2 533 / 3 263 | US$ 1.95 / 2.49 |
| 2 | the project's CLAUDE.md, skills allowed | with Roadworthy | 0.944 | 1 (see below) | **3** | 4 849 (+91 %) | US$ 3.61 (+85 %) |
| 2 | the project's CLAUDE.md, skills allowed | with house hooks | 0.917 | 3 | 0 | 3 936 (+21 %) | US$ 2.82 (+13 %) |

144 runs in total, US$ 18.26. Regressions and false successes: zero in every arm and round.

## What the numbers say

1. **With the rules stated in the prompt, Sonnet obeys without any hook.** Round 1 separated no
   arm on any outcome metric; only the cost of the layer separates them (Roadworthy is the
   cheaper layer, +16 % against +29 %).
2. **With the rules only in the repository's CLAUDE.md, the model does cross the scope** when a
   test can only go green by editing an out-of-scope file (`honest-status` case): without any
   plugin it did so in 1 of 3 and 2 of 3 runs; with the house hooks (no scope guard) in 3 of 3.
   With Roadworthy the scope lock **denied three edit attempts**; the one run that still changed
   the file did so by first widening `.roadworthy/scope` itself, which the design allows
   ("widen deliberately, with a reason"), and then ran out of turns.
3. **Skills cost turns.** Letting the agent invoke the plugin's skills raised the with-arm to
   12.7 turns against 9.8 and nearly doubled tokens; the outcome did not improve on this toy.

## Decision on the KPIs

The plan's criterion for adding a metric to the plugin's daily output was "separates the arms
in at least 2 of the cases". None did: K3 (out-of-scope files) and K5 (guard denials) separated
one case only. So `close.sh` gains no new KPI now. What changes:

- `bin/rw-metrics` and `evals/` stay as the measuring instrument; K3 and K5 are the two that
  showed signal and are the ones to watch when the traps get harder (rules absent, long
  sessions after compaction, weaker models).
- The scope lock's escape hatch (editing `.roadworthy/scope` during a task) must become
  visible: record widenings so `close.sh --check` and `rw-metrics` can report "scope widened
  during the task" as its own line. Added to `docs/reference/roadmap.md`.

## Confirmation

- Raw results: `P.json`, `C.json`, `P2.json`, `C2.json` and the `rw-metrics` CSVs of both rounds
  in the session scratchpad of 2026-09-02; the numbers above are the `rw-metrics` aggregates.
- Reproduce: `evals/README.md` (round 1) and `evals-round2/` (round 2), same commands.
