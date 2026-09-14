# Roadworthy

**English** · [Português (Brasil)](README.pt-BR.md)

**One change, zero collateral damage.**

## TL;DR

Roadworthy is a Claude Code plugin that turns quality rules into hooks. An agent that touches code
does one nice thing and breaks ten others; prose does not stop that, a hook that denies the edit does.

- **No front, no write.** Until a plan declares its scope, every edit and every shell write inside
  the repository is denied, naming the rite that opens a front.
- **Scope declared, scope enforced.** An edit outside the declared globs is denied, and the closing
  refuses a front whose diff left them.
- **No "done" without evidence.** A turn that claims the work is finished is blocked until every
  declared gate ran fresh on the last commit.
- **Commits stay clean.** No forbidden flags, no empty commits; at night no push, merge or tag, and
  the files the project declares frozen stay frozen.

Two commands to install, four steps to a first front, one file to declare your quality bar
(`.roadworthy/gates`). Cost: about 772 tokens on every prompt, measured with `claude plugin details`.
Built on the official plugin format: hooks, skills, agents, user configuration. No daemon, no swarm,
no framework to learn.

## Install

```bash
claude plugin marketplace add aleonnet/Roadworthy
claude plugin install roadworthy@roadworthy
```

Claude Code prompts for the [options](#configuration) on enable. Re-running the two commands is
idempotent; `claude plugin update roadworthy@roadworthy` picks up new versions, and
`/reload-plugins` applies a changed option without losing the conversation.

## Your first front

1. **Plan.** `/roadworthy:plan` writes a plan with its **Scope** (globs) and **Verification**
   (gate commands) as fenced blocks, and `plan-preflight.sh` checks it mechanically before anyone
   reads it.
2. **Open.** `scope-write.sh <plan.md>` writes `.roadworthy/scope`, `.roadworthy/gates` and the
   approval snapshot in one act. From here the fences are on.
3. **Work.** Edits outside the scope are denied; the plan file itself stays editable.
4. **Close.** `/roadworthy:close` runs the gates after the last commit, records each with the tree's
   fingerprint, and releases the scope. Only then may the turn say "done".

## What it enforces (hooks)

| Hook | Event | Guarantee |
|---|---|---|
| `principles` | every prompt | Injects your numbered principles and the project's numbered rules, pins the principles file by digest, and repeats a fence's third denial as a line in the next prompt. |
| `rite-gate` | Edit/Write **and Bash** | No usable `.roadworthy/scope`, no write and no removal inside the repository. The files only a script may write are denied by hand, front or no front; the owner's two files are the owner's. |
| `scope-lock` | Edit/Write | While a scope exists, an edit outside its globs is denied. Watches the edit tools, not the shell; the closing catches the rest. |
| `protect-paths` | Edit/Write | Paths matching `protected_paths` (and the project's `.roadworthy/protected`) are never edited. |
| `guard-commit` | Bash | `git commit` with a forbidden flag (default `--trailer`) or with nothing staged is denied. |
| `plan-review-gate` | ExitPlanMode | A plan leaves plan mode only when the pre-flight is green (default) or a cold review says `VERDICT: APPROVED` (`plan_gate`). |
| `stop-gate` | Stop | A finished claim is blocked while `close.sh --check` does not report every declared gate FRESH. |
| `overnight-guard` | Bash | While `.roadworthy/overnight` exists, push, merge, tag, `gh pr merge` and the project's `deny:` rules are denied. |

<details>
<summary><strong>The fine print, hook by hook</strong> — what each one measures, and the field case that shaped it</summary>

**`principles`.** Injects your numbered principles (bundled set or your own file) plus the numbered
rules of the current project's memory, so they never lose salience in a long session. It also
**pins the principles file by digest**: the file lives outside every repository, so nothing can stop
it being edited — what this does is announce the change at every prompt, naming the digest and the
date last agreed, until you agree to the new text. And when the same fence has denied **three
times** in the open front, that count comes back as a line in the next prompt: an agent does not
remember, but it reads.

**`rite-gate`.** While the project has no usable `.roadworthy/scope`, every edit, every shell write
and every shell removal inside the repository is denied, naming the rite that opens a front. An
**empty** scope file does not count: one `touch` used to satisfy every check while switching the
lock off. Files only a script may write (scope, gates, snapshot, state, ledgers) are denied by hand
with or without a front, **removing anything under `.roadworthy/` is denied** (`rm`, `unlink`,
`rmdir`, `git rm`, the source of `mv`), and the owner's two files — `.roadworthy/protected`,
`.roadworthy/overnight-rules` — are the owner's: the agent neither edits nor removes them. A front
recorded as `gaps_found` or `needs_human` blocks the next one. The plan is exempt in both its homes
(`plans_dir`, and the `plans` directory of `.roadworthy/docs.json`). Measured on this repository on
2026-09-13: 60 edits and 117 shell commands in one day, zero rite invocations, nothing noticed.

**`scope-lock`.** While `.roadworthy/scope` exists in the project, any edit outside the listed globs
is denied. The plan file itself (in either of its two homes) is exempt: it is the rite's own
artefact. **The guard watches the edit tools, not the shell** — a `cat >` or `sed -i` run through
Bash is not seen; see [Declared limits](docs/reference/roadmap.md). What backs it up is the closing:
`close.sh` refuses a front whose diff touched a file outside the globs, and refuses a rite-written
scope whose `plan.snapshot` is gone.

**`protect-paths`.** Paths matching `protected_paths` are never edited, whatever the model decides.

**`guard-commit`.** `git commit` with a forbidden flag (default `--trailer`) or with nothing staged
is denied.

**`plan-review-gate`.** What guards a plan is `plan_gate`. In `preflight` (the default since 0.6.0)
the plan is checked mechanically by `skills/plan/scripts/plan-preflight.sh` and the submission is
denied with that output when it is red — citations that the line does not sustain, scope paths that
do not exist, acceptance numbers with a gap, a declared correction whose old text is still there,
and a scope file that was never read WHOLE in the session, proved from the transcript the harness
writes. Five rounds of cold review on one plan never converged here, and the measured cause was that
every round spent its attention on things a machine can check; the reviewer goes back to the diff,
which is what principle 4 always said. In `review` (and `both`) a plan can only be submitted with a
review that says `VERDICT: APPROVED` — either next to it as `<plan><review_suffix>`, or, in plan mode
where only one file may be written, as a `## Review` section of the plan itself. REJECTED and
ESCALATE deny, round 3 needs the user's `owner:` decision, and a section added after round 1 denies
(growth guard). The plan has two homes and the gate reads both: `plans_dir` (shared by every project)
and the `plans` directory of `.roadworthy/docs.json`. The plan declares `project:` and the gate
elects by that, names a plan that belongs elsewhere, skips one marked superseded, and refuses two
live plans of one project instead of choosing by date. When the call carries the plan's text, the
text picks the file; when nothing matches byte for byte, the plan this session last wrote (from the
transcript) is elected; only then the newest by date — and the gate says so in the context it
returns. A plan may declare `base:`; the ref must resolve and the review must name the same one.

**`stop-gate`.** A turn that says the work is finished is blocked while `close.sh --check` does not
report every declared gate FRESH, and the block shows the state of each one. **Never blocks a
project with no gates file** (that check fails there by design), never blocks the same tree twice —
the latch is keyed on the tree's content, so a changed tree is judged again —, honours the
documented `stop_hook_active` field, and fails open on anything it cannot read. It reads the
project's own evidence, in the environment Claude Code gives a hook (measured 2026-09-14: six FRESH
gates were reported MISSING because the ledger was resolved through a directory shared by every
plugin's projects). Exit 2 is what blocks a turn; the Stop event has its own contract.

**`overnight-guard`.** While `.roadworthy/overnight` exists (set by `/roadworthy:overnight` on the
user's order), `git push`, `git merge`, `git tag`, `gh pr merge` and every `deny:` rule of
`.roadworthy/overnight-rules` are denied; `protect-paths` also freezes the file's `freeze:` globs.

</details>

<details>
<summary><strong>How a hook fails, where the evidence lives, Windows</strong></summary>

Every hook declares its crash policy. The six guards (`rite-gate`, `scope-lock`, `protect-paths`,
`guard-commit`, `overnight-guard`, `plan-review-gate`) **fail closed**: an internal error denies the
action, because a boundary that fails open is not a boundary. The `principles` hook fails open with
a visible notice, because an error on prompt submission must never erase the prompt; `stop-gate`
fails open too, because a session that cannot end is the costlier failure. Denials are structured
JSON decisions, never a bare exit 2 — except `stop-gate`, where exit 2 is the Stop event's own way
of blocking a turn. **Every denial is recorded** in `.roadworthy/denials.jsonl` with the fence, the
reason and the front it happened in, so a guardrail that fires leaves a trace instead of being
visible only in an eval trace nobody has.

**Where the evidence lives.** Ledgers, latch, state and refutation records go to `ROADWORTHY_DATA`
when that variable is set, else to `<repository>/.roadworthy`. Not to `CLAUDE_PLUGIN_DATA`: Claude
Code sets it for every hook to a directory per plugin, shared by every project on the machine, and
a person's shell does not set it at all — writer and reader would never meet (measured 2026-09-14).
The one thing kept there is the pin of the principles file, which lives outside every repository.

**On Windows without bash**, `hooks/run-hook.cmd` refuses instead of passing the call unguarded: a
guard exits 2 with the reason on stderr, `principles` and `stop-gate` warn with exit 1. Executed on
a Windows runner in CI; not executed on the machine that wrote it.

**Cost**, measured with `claude plugin details` on 2026-09-14: about 772 tokens always on; 310 to
3,700 per skill or agent invocation (the plan skill is the 3,700).

</details>

## What it teaches (skills)

| Skill | Use |
|---|---|
| `/roadworthy:plan` | A plan born ready: whole-file reading, impact sweep with commands, EARS acceptance, scope as globs, and `plan-preflight.sh` checking what a reader should never spend attention on. |
| `/roadworthy:refute` | Prove a check can fail: inject the defect, expect the failure text, restore byte for byte, verify the hash. Once per guarantee, when it is born. |
| `/roadworthy:close` | Run the declared gates after the last commit, record each with the tree's fingerprint, release the scope. |
| `/roadworthy:document` | Dated decision records, MADR status vocabulary, revision by new file, a Confirmation section, and the checkers that keep the tree honest. |
| `/roadworthy:resume` | Resume from disk: the map, the newest handoff by name, the state confirmed by command. |
| `/roadworthy:overnight` | Unattended execution of an approved plan, on the user's order only: a diary with script-taken timestamps, publishing frozen until morning, a hand-off to audit on waking. |

And one agent, `cold-reviewer`: read-only, sees only the diff or plan and the criteria, reports only
what affects correctness, fails closed.

<details>
<summary><strong>What each skill runs</strong></summary>

- **plan** — `[NEEDS CLARIFICATION]` instead of assumptions; `scope-write.sh` opens the front from
  the plan's fenced blocks; `plan-preflight.sh` checks citations by content, scope paths, acceptance
  numbering, declared corrections, and whole-file reading proved from the transcript.
- **refute** — `skills/refute/scripts/refute.sh` does it mechanically and writes the record. A
  refutation runs your check twice, so twelve of them cost twelve suite runs: once per guarantee,
  not the whole suite on every change.
- **close** — `close.sh` runs the gates in `.roadworthy/gates`, says FRESH/STALE/MISSING later with
  `--check`; `close-front.sh` moves a closed front into history with links rewritten.
- **document** — `docs-init.sh` builds the tree by role, `docs-check.sh` and `pointers-check.sh`
  keep it honest. Projects that write status words in another language declare them under `status`
  in `.roadworthy/docs.json`.
- **resume** — `resume-pick.sh` picks the handoff by name, never by modification time, and follows
  `superseded by`.
- **overnight** — some teams run the agent unattended on an approved plan and audit the result in
  the morning on the real thing; this makes that routine mechanical. It starts only on the user's
  explicit order: `overnight-start.sh` checks the approved review (by name) and the plan's Overnight
  policy, listing every missing precondition at once; `overnight-entry.sh` records decisions with a
  primary source, phase commits and blockers, and the diary cannot carry an estimated timestamp;
  publishing is denied until the marker is removed; `overnight-close.sh` requires every gate FRESH
  and writes the morning hand-off with the bench table the user fills in. Per-project freezes live
  in `.roadworthy/overnight-rules` (`deny: <regex>` for commands, `freeze: <glob>` for files).
  Record: `docs/decisions/2026-09-03-1322-overnight-mode.md`.

</details>

## Configuration

Set on enable, or later with `/plugin` → Roadworthy → Configure. Values reach the hooks as
`CLAUDE_PLUGIN_OPTION_<KEY>` environment variables.

| Option | Default | Meaning |
|---|---|---|
| `principles_file` | bundled `principles/PRINCIPLES.md` | Markdown file whose numbered lines are injected at every prompt. |
| `project_rules` | `true` | Also inject numbered lines from the project's auto-memory `MEMORY.md`. |
| `protected_paths` | empty | Comma-separated globs Edit/Write may never touch; the project may add its own in `.roadworthy/protected`, which the owner edits outside the agent. |
| `stop_gate` | `true` | Block a finished claim while a declared gate is not FRESH. |
| `rite_gate` | `true` | Deny edits and shell writes while no front is open, and deny writes to the files only a script may write. |
| `scope_lock` | `true` | Honour `.roadworthy/scope`. |
| `forbidden_commit_flags` | `--trailer` | Comma-separated flags denied in commit commands. |
| `block_empty_commits` | `true` | Deny `git commit` with nothing staged. |
| `plan_gate` | `preflight` | What guards a plan: `preflight` checks it mechanically; `review` is the pre-0.6.0 adversarial verdict; `both` is the two. |
| `plan_review_required` | `true` | Require the review before ExitPlanMode. It binds to the plan by name, never by hash: what the user approved is what counts. |
| `max_review_rounds` | `2` | Rounds of cold review a plan may take before only the user's written decision (an `owner:` line) unlocks it. Round 3 does not exist. |
| `review_suffix` | `.review.md` | Suffix of the review file next to the plan. |
| `plans_dir` | `~/.claude/plans` | Where Claude Code writes plan-mode plans. Shared by every project, so a plan declares `project:` in its header. The second home is the `plans` directory of `.roadworthy/docs.json`. |

**A changed option does not reach a session that is already open.** Claude Code reads the options
when it loads the plugin, so after changing one run **`/reload-plugins`** or start a new session.
Measured on 2026-09-13: the option was right on disk, the hook honoured it when the variable reached
it, and the open session kept denying with the old value.

## Testing

```bash
bash tests/run.sh              # the whole gate: 30 cases, ~3 min
bash tests/hooks/scope-lock.sh # one fence, alone, in seconds
bash tests/attack.sh           # the cheating suite: 64 attacks, 50 refused, 14 declared
bash tests/bench/bench.sh      # the fences met by a REAL session, headless (spends a few cents)
```

Every hook is exercised with real stdin JSON in both directions, every script is refuted with a
toy check, every Python block embedded in the shell is compiled and checked for dead imports, the
manifests are validated with `claude plugin validate --strict`, and a privacy scan fails on any
absolute home path. CI runs `tests/run.sh` on macOS and Linux, executes the no-bash branch of
`run-hook.cmd` on Windows, and can run the one Bash-granting eval case on Linux.

<details>
<summary><strong>How the suite is built, and why</strong></summary>

**The suite fires synthetic events; the bench fires a session.** `tests/bench/bench.sh` loads the
working tree's hooks into `claude -p --plugin-dir` on a toy repository, one exact act per prompt,
and reads the harness's own `permission_denials` and the disk: no front → edit denied; the rite
opens the front; edit outside the scope denied; `rm .roadworthy/plan.snapshot` denied; a finished
claim on FRESH gates not blocked; denials in the project ledger. Every release before 0.6.1 shipped
"proved by the suite, unproved in the field"; this is the field.

| Where | What |
|---|---|
| `tests/run.sh` | the runner: reads `tests/cases.txt`, runs each case (four at a time), folds in the attack suite |
| `tests/cases.txt` | **the manifest, and the fence.** A runner that globs a directory loses a case the day the file is deleted and says nothing; this one refuses to run when the list and the directory disagree, in either direction |
| `tests/lib.sh` | `ok`/`fail`, `run_hook`, `denied`, `golden`, the temp root, and `rw_end` |
| `tests/hooks/`, `tests/scripts/`, `tests/meta/` | one case per fence, per script, and for the suite's own hygiene |
| `tests/fixtures/` | the toy repositories, documentation trees, plans and transcripts, built by name |
| `tests/goldens/` | the deny and context envelopes, compared key for key |
| `tests/bench/` | the headless real-session bench, and what each step proves |

**A case is a file you can run alone, and that is the point.** A refutation proves a fence can go
red by injecting the defect and running the check twice. Against a 1407-line monolith that cost two
full suite runs; measured on this repository, the six refutations of `plan-preflight.sh` took 32
minutes of wall clock. Against one case: 5.3 seconds.

**A case that dies before its last assertion is red, by construction.** `rw_end` sets a flag and the
exit handler refuses to report success without it. Measured on bash 3.2, an unbound variable under
`set -u` aborts the script and the `EXIT` trap sees `$?=0`, so the case exits **0** with half its
assertions never run — which is what `tests/run.sh` shipped with before this was found, by the
suite, on itself.

**This suite is what you run on every change; refutation is not.** A refutation exists to prove a
new fence can go red for its own reason, so it belongs to the moment that fence is written — once,
recorded in the check's header — and after that the suite carries it.

</details>

## Evals

`evals/` holds seven cases that measure the guardrails with and without the plugin on the same
prompts; `bin/rw-metrics` turns the run into seven KPIs (task success, regression, out-of-scope
files, false success, denials, tokens, turns). Graders judge the bytes of files and the final
`STATUS:` line, never the attempt. Measured with a smaller model (`--model haiku`) on 2026-09-14:
see `evals/README.md` and `docs/decisions/2026-09-14-1750-evals-com-modelo-menor.md`.

## Declared limits

Some holes are decided, not pending: the scope lock watches the edit tools and not the shell; the
shell command reader is best effort and says so; evidence written on the attacked machine can be
forged; the stop gate judges a named enumeration of "finished" words. Each one is written with its
reason in [`docs/reference/roadmap.md`](docs/reference/roadmap.md) and exercised in `tests/attack.sh`
as a DECLARED attack, so a limit that starts being refused is reported as the fence growing, and a
hole nobody declared fails the gate.

## Principles

The bundled principles are eight numbered lines, each naming the failure it prevents and the
mechanism behind it. Read them in [`principles/PRINCIPLES.md`](principles/PRINCIPLES.md). Keep them,
or point `principles_file` at your own.

## Uninstall

```bash
claude plugin uninstall roadworthy@roadworthy
claude plugin marketplace remove roadworthy
```

## License

MIT.
