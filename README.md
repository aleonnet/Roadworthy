# Roadworthy

**English** · [Português (Brasil)](README.pt-BR.md)

**One change, zero collateral damage.**

## TL;DR

Roadworthy is a Claude Code plugin that turns quality rules into hooks. An agent that touches code
does one nice thing and breaks ten others; prose does not stop that, a hook that denies the edit does.

- **No front, no write.** Until an approved plan declares its scope, every edit and every shell
  write inside the repository is denied, naming the rite that opens a front.
- **Scope declared, scope enforced.** An edit or a named shell write outside the declared globs is
  denied, a commit takes only what the front declared, and the closing refuses a front whose diff
  left them.
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
   (gate commands) as fenced blocks, agrees with you how the front will report (`report:`), and
   `plan-preflight.sh` checks it mechanically before anyone reads it. You approve it in plan mode,
   and the approval is recorded.
2. **Open.** `scope-write.sh <plan.md>` writes `.roadworthy/scope`, `.roadworthy/gates` and the
   approval snapshot in one act — from the plan you approved, and from no other. From here the
   fences are on.
3. **Work.** Edits and named shell writes outside the scope are denied; the plan file itself stays
   editable. Commits take only what the scope covers.
4. **Close.** Write and commit the hand-off, then `/roadworthy:close` runs the gates after the last
   commit, records each with the tree's fingerprint, and releases the scope. Only then may the turn
   say "done".

## What it enforces (hooks)

| Hook | Event | Guarantee |
|---|---|---|
| `session-state` | session start | Says what the rite left on disk: branch, tree, open front and its plan, recorded state, what waits for a person, what the owner requires, the night marker, whether the gates are fresh. Facts, never a verdict. |
| `principles` | every prompt | Injects your numbered principles and the project's numbered rules, pins the principles file by digest, repeats the reporting form agreed for the open front, and records a person's answer to a human verification. |
| `rite-gate` | Edit/Write **and Bash** | No approved front, no write inside the repository. The rite's own files are written by its scripts and by nothing else; the owner's five files are the owner's. With a front open, a named shell write outside the scope is denied. |
| `scope-lock` | Edit/Write | While a scope exists, an edit outside its globs is denied — the scope of the repository the file is in. |
| `protect-paths` | Edit/Write | Paths matching `protected_paths` (and the project's `.roadworthy/protected`) are never edited. |
| `guard-commit` | Bash | A `git commit` is denied with a forbidden flag (default `--trailer`), with nothing staged, or when it would take a protected path or a path outside the open front's scope. |
| `plan-review-gate` | ExitPlanMode | A plan leaves plan mode only when the pre-flight is green and, where the user or the project asks, a cold review says `VERDICT: APPROVED`. When you approve the plan, the approval is recorded. |
| `review-record` | subagent end | Records the cold reviewer's verdict with the commit it was given about, so "a review approved this" has a source other than the agent. |
| `stop-gate` | Stop | A claim that the work is finished is blocked while `close.sh --check` does not report every declared gate FRESH, in every repository the turn wrote in. |
| `overnight-guard` | Bash | While `.roadworthy/overnight` exists, push, merge, tag, `gh pr merge` and the project's `deny:` rules are denied. |

<details>
<summary><strong>The fine print, hook by hook</strong> — what each one measures, and the field case that shaped it</summary>

**`session-state`.** When a session starts, resumes, is cleared or is compacted inside a repository,
the first thing in its context is what is on disk: the branch and its distance from upstream, the
tree, the open front (which plan, since when, from which base), the reporting form agreed for it,
the recorded state, what is waiting for a person, what the owner requires (`.roadworthy/rites`), the
night marker, and whether the declared gates are fresh. Shaped by a session that resumed on the
wrong branch and was told by nothing. It cannot block.

**`principles`.** Injects your numbered principles (bundled set or your own file) plus the numbered
rules of the current project's memory, so they never lose salience in a long session. It also
**pins the principles file by digest**: the file lives outside every repository, so nothing can stop
it being edited — what this does is announce the change at every prompt, naming the digest and the
date last agreed, until you agree to the new text. While a front is open it repeats the **reporting
form** the plan agreed (`report:`). When the same fence has denied **the same way three times** —
this session's main agent, with a scope open, since the front opened — that comes back as a line in
the prompt, and the third denial already says so in its own reason. And it is where **a person
answers a human verification**: a line `rw-human: all approved` (or `rw-human: <item> rejected
<note>`) in your own prompt is recorded; the same command typed by the agent is denied.

**`rite-gate`.** While the repository **the target is in** has no usable `.roadworthy/scope`, every
edit, shell write and shell removal of tracked content there is denied, naming the rite that opens a
front. An **empty** scope file does not count. Shell commands are read by `hooks/shellread.py` the
way the shell reads them — quoting, heredocs, substitutions, every separator, wrappers, `bash -c`,
the directory in force — and its grammar is a table of cases (`tests/scripts/shellread.sh`).
**The front opens only from what you approved:** when the agent runs `scope-write.sh`, the plan's
scope, gates and base must match an approval on record; the owner opens one himself, in a shell of
his own, with `scope-write.sh <plan.md> --owner`, which the agent is denied. **The rite's own directory is closed to
everything but its scripts:** a path under `.roadworthy/` may only be handed to a command known to
read; writing, removing, sweeping (`find -delete`, `git clean`), an interpreter whose code writes
there, and the same directory spelled in another case are denied. The owner's five files —
`protected`, `free`, `rites`, `overnight-rules`, `docs.json` — are the owner's. **With a front
open**, a named shell write outside the scope is denied like an edit, a protected path is protected
through the shell too, a front whose scope or gates no longer match the approval snapshot stops
every write until it is reopened, and a change outside the scope that some program left in the tree
is **said** to the agent (the commit and the closing are where it is refused). What needs no front:
the plan (a `.md` directly in one of its two homes), the session scratchpad, the project memory,
what git ignores, and the paths the owner lists in `.roadworthy/free`. Measured on this repository
on 2026-09-13: 60 edits and 117 shell commands in one day, zero rite invocations, nothing noticed.

**`scope-lock`.** While `.roadworthy/scope` exists in the repository the file is in, any edit outside
the listed globs is denied. The scope that counts is that repository's, never the one the session
happens to stand in; a file in no repository under a temporary directory is nobody's project. The
plan file itself (a `.md` directly in either of its two homes) is exempt: it is the rite's own
artefact. The shell is the entry gate's door, for the targets a reader of commands can name; what a
program writes by itself is caught where the set is exact — the commit and the closing. See
[Declared limits](docs/reference/roadmap.md).

**`protect-paths`.** Paths matching `protected_paths` are never edited, whatever the model decides.

**`guard-commit`.** `git commit` with a forbidden flag (default `--trailer`) or with nothing staged
is denied. And **what enters the history is what the front declared**: the set a commit would take
is read from git's own index — what is staged, what the same command stages, every tracked change
when it says `-a` — and the commit is denied when that set holds a protected path, a path outside
the open front's scope, or, with no front open, anything but the plan, `.roadworthy/gates` and what
the owner freed. It holds however the file was written, which is what the entry gate cannot promise
about a program that opens files by itself. `commit_scope=false` switches it off.

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
**The project may ask for more than your option does:** a `plan_gate:` line in `.roadworthy/rites`
is joined with the option and the stricter wins, so a project whose owner wants every plan reviewed
does not depend on a note the agent may not open. And **when you approve the plan, the approval is
written down** — the fingerprint of its scope, gates and base — which is what the entry gate looks
up before a front opens. Editing the prose afterwards keeps the approval; changing a glob, a gate or
the base needs a new one.

**`review-record`.** When the `cold-reviewer` agent finishes with a `VERDICT:` line, the verdict is
recorded with the commit and tree it was given about. With `diff_review: required` in
`.roadworthy/rites`, the closing only passes with an APPROVED verdict for the commit being closed;
wherever a plan needs a review (`plan_gate` in `review` or `both`), the review file needs the
reviewer's own recorded verdict behind it.

**`stop-gate`.** A turn that says the work is finished is blocked while `close.sh --check` does not
report every declared gate FRESH, and the block shows the state of each one — in the repository the
session stands in and in every other one it wrote in. It judges a **claim**, not a word: the word
does not count in a table row, in a legend of status marks, negated, or followed by "to/when/if",
and a message that names what is still open (`stop_gate_open_markers`) is a status report, not a
claim. **Never blocks a
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
action, because a boundary that fails open is not a boundary — and so does a guard that simply
dies (an unbound variable, a line the shell cannot parse), which used to let the call through. The
`principles` hook fails open with a visible notice, because an error on prompt submission must never
erase the prompt; `stop-gate`, `session-state` and `review-record` fail open too, because a session
that cannot end, cannot start, or a subagent that cannot stop is the costlier failure. Denials are
structured JSON decisions, never a bare exit 2 — except `stop-gate`, where exit 2 is the Stop
event's own way of blocking a turn. **Every denial is recorded** in `.roadworthy/denials.jsonl` with
the fence, the reason, the session, the subagent when there is one, and whether a scope was open —
in the repository the denied target is in, and never by creating that directory in a repository
that has none.

**Where the evidence lives.** Ledgers, latch, state and refutation records go to `ROADWORTHY_DATA`
when that variable is set, else to `<repository>/.roadworthy`. Not to `CLAUDE_PLUGIN_DATA`: Claude
Code sets it for every hook to a directory per plugin, shared by every project on the machine, and
a person's shell does not set it at all — writer and reader would never meet (measured 2026-09-14).
The one thing kept there is the pin of the principles file, which lives outside every repository.

**On Windows without bash**, `hooks/run-hook.cmd` refuses instead of passing the call unguarded: a
guard exits 2 with the reason on stderr; `principles`, `stop-gate`, `session-state` and
`review-record` warn with exit 1. Executed on a Windows runner in CI; not executed on the machine
that wrote it.

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

- **plan** — `[NEEDS CLARIFICATION]` instead of assumptions; one question about how the front will
  report, written in the plan's `report:` line; `scope-write.sh` opens the front from the plan's
  fenced blocks, keeps the base when the same front is reopened, and refuses a second front over a
  live one; `plan-preflight.sh` checks citations by content, scope paths, acceptance numbering,
  declared corrections, and whole-file reading proved from the transcript.
- **refute** — `skills/refute/scripts/refute.sh` does it mechanically and writes the record. A
  refutation runs your check twice, so twelve of them cost twelve suite runs: once per guarantee,
  not the whole suite on every change.
- **close** — `close.sh` runs every gate in `.roadworthy/gates` with its input isolated and refuses
  when fewer ran than were declared; says FRESH/STALE/MISSING later with `--check`; refuses a front
  whose diff touched a protected path or left the scope. A human verification has a state of its
  own: `--needs-human "<item>"` opens one, `--human` lists what is open, the person's answer closes
  it, and no later closing erases it. `--abandon "<reason>"` ends a front that has no way forward,
  on record. `close-front.sh` moves a closed front into history with links rewritten.
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
| `stop_gate_open_markers` | status marks, `TODO`, "still have to", "in progress" | Comma-separated marks; a final message that carries one outside a legend line names an open item and is not judged as a finished claim. |
| `session_state` | `true` | Say the state on disk when a session starts, resumes, is cleared or is compacted. |
| `rite_gate` | `true` | Deny edits and shell writes while no front is open, and deny writes to the files only a script may write. |
| `scope_lock` | `true` | Honour `.roadworthy/scope`. |
| `forbidden_commit_flags` | `--trailer` | Comma-separated flags denied in commit commands. |
| `block_empty_commits` | `true` | Deny `git commit` with nothing staged. |
| `commit_scope` | `true` | Deny a commit that would take a protected path, a path outside the open front's scope, or — with no front open — anything but the rite's own artefacts. |
| `plan_gate` | `preflight` | What guards a plan: `preflight` checks it mechanically; `review` is the pre-0.6.0 adversarial verdict; `both` is the two. |
| `plan_review_required` | `true` | Require the review before ExitPlanMode. It binds to the plan by name, never by hash: what the user approved is what counts. |
| `max_review_rounds` | `2` | Rounds of cold review a plan may take before only the user's written decision (an `owner:` line) unlocks it. Round 3 does not exist. |
| `review_suffix` | `.review.md` | Suffix of the review file next to the plan. |
| `plans_dir` | `~/.claude/plans` | Where Claude Code writes plan-mode plans. Shared by every project, so a plan declares `project:` in its header. The second home is the `plans` directory of `.roadworthy/docs.json`. |

**A changed option does not reach a session that is already open.** Claude Code reads the options
when it loads the plugin, so after changing one run **`/reload-plugins`** or start a new session.
Measured on 2026-09-13: the option was right on disk, the hook honoured it when the variable reached
it, and the open session kept denying with the old value.

<details>
<summary><strong>What the project declares</strong> — the files under <code>.roadworthy/</code> that are yours</summary>

The options above are the user's and are born permissive. What a PROJECT requires lives in the
project, in files the agent can read and cannot edit or remove (one glob or one `key: value` per
line, `#` starts a comment):

| File | What it says |
|---|---|
| `.roadworthy/gates` | The commands a closing runs, one per line. Written by `scope-write.sh` from the plan's Verification block and versioned like a test. |
| `.roadworthy/protected` | Globs nobody edits, through any door: the edit tools, the shell, the commit, the closing. |
| `.roadworthy/free` | Globs that need no front and no scope: private notes, drafts, a scratch area inside the repository. |
| `.roadworthy/rites` | What this project demands beyond the plugin's defaults: `plan_gate: preflight\|review\|both`, `diff_review: required`. A word it does not know refuses instead of meaning "no requirement". |
| `.roadworthy/overnight-rules` | `deny: <regex>` for commands and `freeze: <glob>` for files while the night marker exists. |
| `.roadworthy/docs.json` | The documentation map, the status words, and the `plans` directory. |

Everything else there (`scope`, `plan.snapshot`, `state`, the `.jsonl` ledgers) is the rite's local
state: written by its scripts, ignored by git in your clone from the moment a front opens, and never
edited by hand.

</details>

## Testing

```bash
bash tests/run.sh              # the whole gate: 34 cases, ~9 min
bash tests/hooks/scope-lock.sh # one fence, alone, in seconds
bash tests/attack.sh           # the cheating suite: 148 attacks, 132 refused, 16 declared
bash tests/bench/bench.sh      # the fences met by a REAL session, headless (spends a few cents)
```

Every hook is exercised with real stdin JSON in both directions, every script is refuted with a
toy check, every Python block embedded in the shell is compiled and checked for dead imports, the
manifests are validated with `claude plugin validate --strict`, and a privacy scan fails on any
absolute home path. CI runs `tests/run.sh` on macOS and Linux, executes the no-bash branch of
`run-hook.cmd` on Windows, and can run the one Bash-granting eval case on Linux.

Working on the plugin itself: [`README_DEV.md`](README_DEV.md) explains how it is built and what
has to stay true when you change it, and [`docs/guides/runbook.md`](docs/guides/runbook.md) has
the steps for each recurring task.

<details>
<summary><strong>How the suite is built, and why</strong></summary>

**Between the two sits the simulator.** `tests/sim/rite-sim.py` drives whole sessions — tool call
after tool call — through every hook `hooks.json` registers, executes each call in a toy repository
when no hook denies it, and then asks the repository what happened. `tests/meta/rite-liveness.sh`
runs its scenarios in two kinds: an honest agent, state after state, where a step denied that should
have passed is a **dead end**; and an agent trying to get past the rite, where nothing the rite
forbids may be true at the end. Its first run found a shell write outside the scope going through
with a front open, and `git commit -am` refused as an empty commit.

**The suite fires synthetic events; the bench fires a session.** `tests/bench/bench.sh` loads the
working tree's hooks into `claude -p --plugin-dir` on a toy repository, one exact act per prompt,
and reads the harness's own `permission_denials` and the disk: no front → edit denied; the agent
opening a front from a plan nobody approved → denied; the owner opens it; a shell write and an edit
outside the scope denied; `rm .roadworthy/plan.snapshot` denied; a finished claim on FRESH gates not
blocked; denials in the project ledger. Every release before 0.6.1 shipped
"proved by the suite, unproved in the field"; this is the field.

| Where | What |
|---|---|
| `tests/run.sh` | the runner: reads `tests/cases.txt`, runs each case (four at a time), folds in the attack suite |
| `tests/cases.txt` | **the manifest, and the fence.** A runner that globs a directory loses a case the day the file is deleted and says nothing; this one refuses to run when the list and the directory disagree, in either direction |
| `tests/lib.sh` | `ok`/`fail`, `run_hook`, `denied`, `golden`, the temp root, and `rw_end` |
| `tests/hooks/`, `tests/scripts/`, `tests/meta/` | one case per fence, per script, and for the suite's own hygiene |
| `tests/fixtures/` | the toy repositories, documentation trees, plans and transcripts, built by name |
| `tests/goldens/` | the deny and context envelopes, compared key for key |
| `tests/sim/` | the session simulator and its scenarios (`live-*` honest work, `att-*` attempts to get past the rite) |
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

Roadworthy closes the paths an agent takes by carelessness or by shortcut. It does not claim to
stop an agent that sets out to defeat it, and the reason is structural: the agent and the hooks run
as the same user, so what a hook can read or write a program started by the agent can reach too.
Measured by an adversarial simulation on 2026-10-01 (record in `docs/decisions/`), three things
remain possible for a deliberate agent: a commit made by a route no reader of commands recognises
(a script on disk, git's own plumbing) puts a file outside the scope in the history, where the
closing then refuses the front; the evidence ledger and the state file can be written by a program
that builds their path at run time — the scope, the gates and the snapshot are caught afterwards by
their digests, the ledger is not; and a claim that the work is finished, worded outside the stop
gate's vocabulary, is not judged. Each one is written with its reason in
[`docs/reference/roadmap.md`](docs/reference/roadmap.md) and exercised in `tests/attack.sh` as a
DECLARED attack, so a limit that starts being refused is reported as the fence growing, and a hole
nobody declared fails the gate.

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
