# Roadworthy

**One change, zero collateral damage.**

Roadworthy is a Claude Code plugin that turns quality rules into mechanisms. Agents that
touch code do one nice thing and break ten others; instructions in prose do not stop that,
hooks do. Roadworthy locks edits to a declared scope, refuses commits that carry forbidden
flags or nothing staged, refuses plans that were not reviewed against their exact bytes, and
gives the agent the tools to prove its guarantees can fail before it calls them guarantees.

Built on the official Claude Code plugin format: hooks, skills, agents, user configuration.
No daemon, no swarm, no framework to learn.

## Install

```bash
claude plugin marketplace add aleonnet/Roadworthy
claude plugin install roadworthy@roadworthy
```

Claude Code prompts for the options below on enable. Re-running the two commands is
idempotent; `claude plugin update roadworthy@roadworthy` picks up new versions.

## What it enforces (hooks)

| Hook | Event | Guarantee |
|---|---|---|
| `principles` | every prompt | Injects your numbered principles (bundled set or your own file) plus the numbered rules of the current project's memory, so they never lose salience in a long session. |
| `scope-lock` | Edit/Write | While `.roadworthy/scope` exists in the project, any edit outside the listed globs is denied. |
| `protect-paths` | Edit/Write | Paths matching `protected_paths` are never edited, whatever the model decides. |
| `guard-commit` | Bash | `git commit` with a forbidden flag (default `--trailer`) or with nothing staged is denied. |
| `plan-review-gate` | ExitPlanMode | A plan can only be submitted with a review file for it (by name) that says `VERDICT: APPROVED`; REJECTED and ESCALATE deny, round 3 needs the user's `owner:` decision, and a section added after round 1 denies (growth guard). The submitted plan text picks the file, not the newest file in the shared directory. |
| `overnight-guard` | Bash | While `.roadworthy/overnight` exists (set by `/roadworthy:overnight` on the user's order), `git push`, `git merge`, `git tag`, `gh pr merge` and every `deny:` rule of `.roadworthy/overnight-rules` are denied; `protect-paths` also freezes the file's `freeze:` globs. |

Every hook declares its crash policy. The four guards **fail closed**: an internal error denies
the action, because a boundary that fails open is not a boundary. The `principles` hook fails
open with a visible notice, because an error on prompt submission must never erase the prompt.
Denials are structured JSON decisions, never a bare exit 2.

Measured with `claude plugin details`: about 468 tokens always on, 220 to 530 per skill or agent
invocation.

## Overnight mode

Some teams run the agent unattended on an approved plan and audit the result in the morning on
the real thing. `/roadworthy:overnight` makes that routine mechanical: it starts only on the user's
explicit order, the decision diary cannot carry an estimated timestamp, publishing and version
bumps are denied until the marker is removed, and the close writes the hand-off with the bench
table. Per-project freezes live in `.roadworthy/overnight-rules` (`deny: <regex>` for commands,
`freeze: <glob>` for files). Record: `docs/decisions/2026-09-03-1322-overnight-mode.md`.

## What it teaches (skills)

| Skill | Use |
|---|---|
| `/roadworthy:plan` | A plan born ready: whole-file reading, impact sweep with commands, EARS acceptance criteria, `[NEEDS CLARIFICATION]` instead of assumptions, scope declaration, hash-bound review. |
| `/roadworthy:refute` | Prove a check can fail: inject the defect, expect the intended failure text, restore byte for byte, verify the hash. `scripts/refute.sh` does it mechanically. |
| `/roadworthy:close` | `close.sh` runs the gates declared in `.roadworthy/gates` after the last commit, records each with the content fingerprint of the tree, and says FRESH/STALE/MISSING later; `close-front.sh` moves a closed front into history with links rewritten. |
| `/roadworthy:document` | Dated decision records with MADR status vocabulary, revision by new file, a Confirmation section; `docs-init.sh` builds the tree by role, `docs-check.sh` and `pointers-check.sh` keep it honest. Projects that write status words in another language declare them under `status` in `.roadworthy/docs.json`. |
| `/roadworthy:resume` | Resume from disk: read the map, pick the newest handoff by name (`resume-pick.sh`), confirm the state, declare what was read. |
| `/roadworthy:overnight` | Unattended execution of an approved plan, only on the user's order: `overnight-start.sh` checks the approved review (by name) and the plan's Overnight policy (English or Portuguese title), listing every missing precondition at once and opens a diary whose timestamps are taken by script; `overnight-entry.sh` records decisions with a primary source, phase commits and blockers; `overnight-close.sh` requires every gate FRESH and writes the morning hand-off. |

And one agent, `cold-reviewer`: read-only, sees only the diff or plan and the criteria,
reports only what affects correctness, fails closed.

## Evals

`evals/` holds seven cases that measure the guardrails with and without the plugin on the same
prompts; `bin/rw-metrics` turns the run into seven KPIs (task success, regression,
out-of-scope files, false success, denials, tokens, turns). See `evals/README.md`.

## Configuration

Set on enable, or later with `/plugin` → Roadworthy → Configure. Values reach the hooks as
`CLAUDE_PLUGIN_OPTION_<KEY>` environment variables.

| Option | Default | Meaning |
|---|---|---|
| `principles_file` | bundled `principles/PRINCIPLES.md` | Markdown file whose numbered lines are injected at every prompt. |
| `project_rules` | `true` | Also inject numbered lines from the project's auto-memory `MEMORY.md`. |
| `protected_paths` | empty | Comma-separated globs Edit/Write may never touch; the project may add its own in `.roadworthy/protected`. |
| `scope_lock` | `true` | Honour `.roadworthy/scope`. |
| `forbidden_commit_flags` | `--trailer` | Comma-separated flags denied in commit commands. |
| `block_empty_commits` | `true` | Deny `git commit` with nothing staged. |
| `plan_review_required` | `true` | Require the hash-bound review before ExitPlanMode. |
| `review_suffix` | `.review.md` | Suffix of the review file next to the plan. |
| `plans_dir` | `~/.claude/plans` | Where Claude Code writes plan-mode plans. |

## Principles

The bundled principles are thirteen numbered lines, each naming the failure it prevents and
the mechanism behind it. Read them in [`principles/PRINCIPLES.md`](principles/PRINCIPLES.md).
Keep them, or point `principles_file` at your own.

## Testing

```bash
bash tests/run.sh
```

Every hook is exercised with real stdin JSON in both directions, every script is refuted
with a toy check, the manifests are validated with `claude plugin validate --strict`, and a
privacy scan fails on any absolute home path. CI runs the same script on macOS and Linux.

## Uninstall

```bash
claude plugin uninstall roadworthy@roadworthy
claude plugin marketplace remove roadworthy
```

## License

MIT.
