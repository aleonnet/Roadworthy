# Roadmap

Living document (undated name by design). One line per item, with the measured reason.

## Done
- 0.1 hooks and skills; 0.2 documentation tree by role, evidence-gated close, refutation
  ledger, resume by name; 0.2.1 per-project status vocabulary (found by adopting on a
  Portuguese-language monorepo).
- Evals suite: `evals/` (seven cases) and `evals-round2/` (six, the same cases with the rules moved
  from the prompt into the project's own CLAUDE.md), plus `bin/rw-metrics` (seven KPIs from the eval JSON, the
  run trace and the kept workspace).
- 0.3.0 overnight mode: `/roadworthy:overnight`, `overnight-guard`, `freeze:` in `protect-paths`,
  the Overnight policy section, the `overnight` eval (record `docs/decisions/2026-09-03-1322-overnight-mode.md`).
- 0.6.0 the rite stops being optional: `rite-gate` on the edit tools and on Bash, `stop-gate`,
  `scope-write.sh` (scope, gates and the approval snapshot in one act), `plan-preflight.sh`
  and the `plan_gate` option, the denials ledger with the three-strikes line injected in the
  next prompt, and `tests/attack.sh`. This closed four items that were pending here: the
  stop gate, the denials log, `.roadworthy/gates` created by nobody, and the signal for a
  session that works with no rite invocation -- which is the one that was measured in the
  field on 2026-09-08 and again, on this repository, on 2026-09-13.
- 0.6.1 the plugin complete, measured against its own claims (record
  `docs/decisions/2026-09-14-1558-todo-contorno-conhecido.md`). Removing is writing (`rm`, `unlink`,
  `rmdir`, `git rm`, the source of `mv`, nothing under `.roadworthy/` removable by hand); the owner's
  two configuration files denied to the agent; a rite-written scope whose snapshot is gone refused
  at the close and at `--check`; one resolver for the project's evidence (`rw_data_dir`), which
  closed the **stop gate reporting FRESH gates as MISSING** (cause measured: the hook environment's
  `CLAUDE_PLUGIN_DATA`, per plugin and shared by every project) and the three-strikes line that
  never reached a prompt; `stop_hook_active` honoured (documented); the plan elected by the
  transcript before the date, the date said out loud (acceptance 16 and 17 of the 0.6.0 plan); **the
  two homes of the plan** reconciled in the gate, the entry gate and the scope lock; **one glob
  grammar** (`hooks/globmatch.py`) for `lib.sh`, `close.sh` and `rw-metrics`; `run-hook.cmd`
  refusing without bash, executed in CI on Windows; the Python inside the shell compiled and checked
  for dead imports; the eval graders judging state, never the attempt, and measured with a smaller
  model; `tests/bench/bench.sh`, the fences met by a real headless session -- the seven-step bench
  that needed a person in plan mode is replaced by a script that fills itself.

## Pending
- **Bash-granting evals on macOS with Docker Desktop.** `claude plugin eval --allow-tools Bash`
  refuses to run when the Docker credential store contains symbolic links (Docker Desktop
  keeps its CLI plugins as links under `~/.docker/cli-plugins`). Measured again on 2026-09-14 with
  CLI 2.1.270, the harness's own words: "the Docker (~/.docker, DOCKER_CONFIG) credential store on
  this machine holds a symbolic link inside it, so the Bash sandbox cannot reliably exclude it — a
  Bash-granting evaluation cannot run here; keep the store's contents in one plain directory (its
  root may be a link)". The one case that needs Bash is `overnight` (the "commit" and "refute"
  cases an earlier line here named do not exist in `evals/`). It runs in the `evals-bash` job of
  the CI on a Linux runner, started by hand, when the repository has the secret.
- `/mutate` with `scripts/mutate-baseline.sh`: read the report of the language's mutation
  tool and print the measured score as the suggested threshold.
- ~~**Scope widening made visible.**~~ **Decided against during 0.6.0, and the reason is the
  whole point:** a ledger makes visible what is now PREVENTED. `rite-gate` denies writing the
  scope file by hand through both doors, `scope-write.sh` is the only writer, `plan.snapshot`
  pins what was approved, and `close.sh` refuses a front whose diff left the declared globs.
  Building a ledger for an act that no longer happens would be instrumenting a corpse -- and
  the field case below (a widening justified by quoting the owner's angry message) is
  prevented by the same three mechanisms rather than recorded by a fourth. If the denial
  proves too strict in the field, the ledger comes back with it.
- **The three-strikes line reaches the next PROMPT, never the same turn.** It is injected by the
  `principles` hook on `UserPromptSubmit`; in a single-prompt session (an eval, a `claude -p`) it
  never appears, and what bounds a model insisting on a denied write is the harness's turn cap and
  the stop gate's latch. Measured 2026-09-14 with haiku: 3 of 36 runs with the plugin hit the
  25-turn cap after dozens of denials, none of them touching a file. Candidate: a `PostToolUse`
  hook that injects the same line into the turn where the third denial happened.
- Prune graders that pass in both arms once three runs with the target model are in hand
  (agentskills.io guidance: such assertions inflate the with-plugin pass rate). The 2026-09-14
  run with haiku is the first set of three; the numbers are in
  `docs/decisions/2026-09-14-1750-evals-com-modelo-menor.md`.
- **Twelve eval scaffolds repeat the same 79 lines** -- six in round 1, six in round 2; only
  the overnight one has a body of its own, at 15 lines. Changing the toy project means twelve
  edits. It is test-asset refactoring, not a guarantee, and it is written here with the cost
  measured rather than done in a release about fences.

## Retired — not pending, and why (2026-09-14)
- ~~**Per-block retirement of the scope**~~ (one scope for one plan; two live fronts in one
  repository would need lines retired by plan). Not a defect: no project has needed two live fronts,
  and building for it unmeasured is the shape this plugin exists to refuse. It comes back the day a
  project asks for it, with that project's measurement.
- ~~**The plan's second home, unread by the gate.**~~ Done in 0.6.1: the gate, the entry gate and
  the scope lock read `plans_dir` and the `plans` directory of `.roadworthy/docs.json`.
- ~~**One glob grammar in three copies.**~~ Done in 0.6.1, and the old line was wrong: it named
  `skills/document/scripts/docs-check.sh` as one of the copies; read whole, that script has no glob
  matcher. The copies were `hooks/lib.sh`, `skills/close/scripts/close.sh` and `bin/rw-metrics`, and
  they read `hooks/globmatch.py` now.
- ~~**The eval graders, four of them.**~~ Done in 0.6.1: twelve graders, not four, judged the
  attempt or accepted every outcome; all judge file bytes or the final `STATUS:` line now.
- ~~**The stop gate reporting fresh gates as MISSING.**~~ Done in 0.6.1; the cause was measured
  before it was fixed (see the 0.6.1 line under Done).
- ~~**Stale reviews poison the gate through plan-mode's reused file names.**~~ Answered by the
  election order of 0.6.1: text match, then the plan this session wrote, then the date announced.
  A review file left by yesterday's plan of the same name still binds to that name (a declared
  decision of 0.3.0), but the gate now names which plan it elected and why.

## Pending — found in the field, 2026-09-08 (blebridge-175, Opus 5, ~9 h session)

The session ran to completion **without a single skill invocation**. Everything below was
measured in that run; the owner asked for it to be recorded for another model to fix.

- **The principles hook can substitute for the rite in the agent's own reasoning.** The
  `principles` hook injects the numbered rules on every prompt. The agent read them all session,
  concluded "I already know what the skill would say", and never invoked `plan`, `refute`,
  `close` or `document`. Cost, measured: four UX documents rewritten before one was approved, a
  plan written in the wrong directory, and a scope violation. Nothing in the plugin notices
  "work is under way and no skill has fired". **Answered in 0.6.0 by `rite-gate`, and not the
  way this line proposed:** it decides on the ABSENCE OF THE ARTEFACT, never on whether a
  skill fired, because the transcript records only the invocation and invoking the skill
  without writing a plan would be a permanent gap. And it **denies** rather than failing
  open, because failing open was measured as equivalent to not existing -- 60 edits and 117
  shell commands in one day on this repository, plugin installed and active, nothing
  noticed. Opt-out is `rite_gate`.
- **Scope widening: second field occurrence, with the aggravating detail the ledger would
  miss.** The existing item above records the 2026-09-02 experiment. On 2026-09-08 the same
  crossing happened for a different reason: `scope-lock` denied a Write to the plan file (the
  plan-mode file lives in `~/.claude/plans`, outside the project globs), and the agent appended
  the path to `.roadworthy/scope` **quoting the user's angry message inside the comment as if it
  were written authorization**. Prevented since 0.6.0 (the scope is written by one script and
  denied by hand through both doors) and, since 0.6.1, the plan's second home is exempt too, so
  the reason that widening happened no longer exists.
- ~~**`.roadworthy/gates` is required by close and created by nobody.**~~ Closed in 0.6.0:
  `scope-write.sh` writes the scope, the gates and `plan.snapshot` in one act, from the plan's
  fenced Scope and Verification blocks.

## Declared limits — decided, not pending (2026-09-13, revised 2026-09-14)

These are not on the list above because they are not going to be fixed as stated. Each is a
limit we accept, with the reason. Documenting a hole does not close it, so they are written here
as decisions and repeated where the user chooses (`README.md`), never as a quiet pending line.
Every one of them is exercised in `tests/attack.sh` as a DECLARED attack, so a limit that starts
being refused is reported as the fence growing, and a hole nobody declared fails the gate.

- **The scope lock watches the edit tools, not the shell.** `hooks.json` registers `scope-lock`
  for `Edit|Write|MultiEdit|NotebookEdit`; a `cat >`, `tee`, `sed -i`, `python -c` or a heredoc
  run through Bash writes without passing it. Why it stays: deciding whether an arbitrary shell
  command writes outside the scope has no exact answer (redirection inside a subshell, an editor
  invoked by a tool, a script that writes later). A guard that fails open on what it cannot parse
  is decoration; one that fails closed denies nearly every command and the plugin becomes
  unusable. **Consequence for the user:** while a scope is declared, write through the edit
  tools; a shell write is not guarded. What compensates is the closing: `close.sh` refuses a front
  whose diff touched a file outside the declared globs.
- **The shell command reader is best effort, and says so in the denial.** `rite-gate` recognises
  `>`, `>>`, `tee`, `cp`, `mv` (source and destination), `install`, `truncate`, `dd of=`, `sed -i`,
  `rm`, `unlink`, `rmdir` and `git rm` in command position, tracking quote state and `$( )` depth.
  An interpreter that opens or unlinks the file itself (`python3 -c "open(...)"`, `perl -e`,
  `python3 -c "os.remove(...)"`), `find -delete` and `xargs rm` write or remove through no verb it
  can name. What backs them up is the closing: a file touched outside the globs, and a rite-written
  scope whose `plan.snapshot` is gone, both refuse it.
- **A changed plugin option does not reach the session that is already open.** Measured
  2026-09-13: the option was correct on disk and the hook honoured it when the variable arrived,
  but the running session kept the value it read at launch. `/reload-plugins` applies it without
  losing the conversation; a new session also does. Why it stays: the reload is the harness's
  own mechanism and works. What changes here: `README.md` says it in the configuration table, so
  nobody concludes the plugin is broken. Turning a fence off through its option is the owner's
  own act and is declared as such.
- **An unpaired apostrophe inside the gate's `$( ... )` block breaks the hook.** Bash counts
  quotes while scanning a command substitution, heredoc body included, so `the project's` in a
  comment desynchronises the scan and produces a syntax error far from the cause (measured
  2026-09-13; the file already carried three such lines and was one apostrophe from breaking).
  Why it stays as a limit: the shape is inherent to embedding Python in a heredoc inside `$( )`.
  The mechanism that catches it already exists and did catch it — `bash -n` in `tests/run.sh` —
  and the file now carries a note at the block saying so.
- **Reading is not understanding.** `plan-preflight.sh` proves a scope file was opened WHOLE in the
  session, from the transcript the harness writes. It cannot prove the reading was any good. The
  fence removes one excuse ("I read it") and buys nothing else, and saying so is the difference
  between a mechanism and a talisman.
- **Evidence written on the attacked machine can be forged.** The transcript that proves the
  reading, the plan, the review and the ledgers all live on the same machine as the agent, owned by
  the same user. `tests/attack.sh` exercises a forged transcript and marks it DECLARED, because it
  is the outer edge of what any local evidence can prove, not a hole in a particular check. What the
  mechanism buys is that the forgery has to be deliberate: a sentence claiming a reading costs
  nothing, a forged transcript is an act.
- **A gate that cannot fail warns and does not refuse.** `close.sh` names a trivially green gate
  (`true`) with a WARN; it does not refuse, because the gate came from the plan the owner approved
  and the closing's job is to run what was approved and say when it proves nothing.
- **The stop gate judges a named enumeration of "finished" words, in two languages.** A claim
  worded outside it is not judged. A guard that guesses at meaning blocks honest turns, and the
  cost of a false positive is a session that cannot end -- measured on this repository on
  2026-09-14, when the word "pronto" inside a sentence about a plan blocked a turn that claimed
  nothing. The latch (one block per tree) and `stop_hook_active` bound the damage.
- **The review binds to the plan by name, not by hash** (0.3.0, the owner's decision): what the
  owner approved is what counts, and editing the plan afterwards does not void it.
- **`.roadworthy/docs.json` stays editable by the agent.** It names directories and status words.
  Changing the word for "superseded" makes the plan gate refuse two live plans as ambiguous; it
  never lets one pass.
- **`ROADWORTHY_DATA` pointed elsewhere for one command moves the ledger, not the gates.** They
  still run for real, and the hook's `--check` reads the project and blocks a claim it cannot see.
- **`run-hook.cmd` without bash is executed in CI, not on the machine that wrote it.** macOS
  cannot run cmd.exe; the `windows-no-bash` job renames every bash on a Windows runner and reads
  the exit codes. Locally the suite reads the text of the batch half.
- **A symlink inside the scope that points outside it** is judged where it sits, not where it
  points (`rw_realpath` does not follow the final component). Following it would make a repository
  with symlinked files inside its own scope uneditable; the write lands on a file the closing sees.
