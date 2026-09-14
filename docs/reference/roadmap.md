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

## Pending
- **Bash-granting evals on macOS with Docker Desktop.** `claude plugin eval --allow-tools Bash`
  refuses to run when the Docker credential store contains symbolic links (Docker Desktop
  keeps its CLI plugins as links under `~/.docker/cli-plugins`); `DOCKER_CONFIG` does not
  bypass the check because both locations are inspected. Consequence: the `commit` (forbidden
  flag, empty staging) and `refute` cases cannot run locally; both guards are covered by the
  unit gate (`tests/run.sh`), not by the experiment. Plan: run those two cases in CI on a
  Linux runner, where the store is a plain directory.
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
- Prune graders that pass in both arms once three runs with the target model are in hand
  (agentskills.io guidance: such assertions inflate the with-plugin pass rate).

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
  were written authorization**. The proposed `{ts, before, after, cwd}` ledger would not catch
  that: the diff looks legitimate. Capture the **reason comment** too, and have `close.sh
  --check` and `rw-metrics` print it verbatim — a widening justified by a quote from the chat is
  exactly the shape to surface.
- **Stale reviews poison the gate through plan-mode's reused file names.** `plan-review-gate`
  binds the review to the plan **by name** and picks the newest matching review by mtime. Plan
  mode generates transient names from the first prompt (e.g.
  `leia-users-alessandro-development-blebri-transient-cocke.md`), and the same name comes back in
  a later, unrelated session. Measured: `ExitPlanMode` was denied with a growth complaint naming
  a section (`Nota de fechamento (2026-09-07 21:05)`) belonging to the **previous day's plan about
  a different subject**, whose review file was still in the directory. Candidates: age out
  reviews whose plan file mtime is older than the review; or bind the review to the plan's
  content hash in addition to the name; or refuse when the newest review predates the plan.
- **Two canonical homes for a plan, and no reconciliation.** The gate only reads
  `PLANS_DIR` (default `~/.claude/plans`). The house documentation norm (global `CLAUDE.md`)
  puts plans in `<repo>/docs/` with a dated name. An agent that follows the documentation norm
  writes a plan the gate cannot see, and gets "no plan found" — measured on 2026-09-08. Neither
  the `plan` skill nor the `document` skill mentions the other's location. Candidate: the `plan`
  skill states the plans directory is the gate's input and the `docs/` copy is the durable
  record, or the gate also searches a project-declared path.
- ~~**`.roadworthy/gates` is required by close and created by nobody.**~~ Closed in 0.6.0:
  `scope-write.sh` writes the scope, the gates and `plan.snapshot` in one act, from the plan's
  fenced Scope and Verification blocks.
- **The scope file has no machine-readable link to the plan that justified each line.** Partly
  closed in 0.6.0: `plan.snapshot` records which plan the globs came from, and hand-editing the
  scope is denied through both doors, so ad-hoc widenings do not accumulate. What is NOT done is
  per-block retirement: a front still writes one scope for one plan. Left here because no
  project has yet needed two live fronts in one repository, and building for it unmeasured is
  the shape this plugin exists to refuse.

## Pending — named in the 0.6.0 reading, not fixed in it

- **The eval graders, four of them, one by one.** `evals/scope/graders/status.md:4` accepts
  `passed|gaps_found|needs_human`, which is every outcome, so it passes in both arms.
  `evals/document/graders/no-code.md` counts the ATTEMPT (`type: 'tool_used'`, `max: 0`), so it
  fails the with-plugin arm exactly when the fence denies the edit -- inverting the sign of the
  experiment -- while `evals/README.md:18` declares the opposite. `evals/protected/graders/reported.md:4`
  matches a word that is already in the prompt, so editing the protected file and saying so
  scores like refusing. Each has a twin in round 2. Why not fixed in 0.6.0: `claude plugin eval
  --allow-tools Bash` is refused on this machine by the Docker credential defect above, so any
  fix would be written and never measured -- the exact class 0.6.0 exists to fence.
- **`allowed_tools` in the prompt against `--allow-tools` on the command line.** The six round-2
  prompts declare `[Read, Glob, Grep, Skill]`, with no `Edit` and no `Write`;
  `evals-round2/README.md:27` says to run with `--allow-tools Write Edit`; and the experiment
  record reports edits that happened. Which one wins is **not determinable from this
  repository**, and the command is refused here, so it is written down rather than guessed.
- **Three independent glob matchers**: `hooks/lib.sh`, `skills/document/scripts/docs-check.sh`
  and `bin/rw-metrics:34-42`. Only the first had the unanchored-name defect, fixed in 0.6.0.
  Not unified because `rw-metrics` runs outside the hook process and does not import `lib.sh`;
  unifying would mean packaging the plugin as a module, which is a larger change than the
  defect it prevents.
- **Twelve eval scaffolds repeat the same 79 lines** -- six in round 1, six in round 2; only
  the overnight one has a body of its own, at 15 lines. Changing the toy project means twelve
  edits. It is test-asset refactoring, not a guarantee, and it is written here with the cost
  measured rather than done in a release about fences.

- **`stop-gate` blocked a turn whose gates were FRESH.** Measured 2026-09-14, in the first session
  the gate ever ran in: it reported all six declared gates as `MISSING` — not `STALE` — and one
  minute later `close.sh --check` reported all six `FRESH`, both from the working tree and from the
  installed copy. `MISSING` is the symptom of having looked in a different evidence ledger:
  `close.sh` resolves it through `ROADWORTHY_DATA` / `CLAUDE_PLUGIN_DATA`, and a hook's environment
  is not the shell's (in the shell both are unset and the ledger falls where the evidence is,
  `.roadworthy/evidence.jsonl`). Candidate: have `stop-gate` pass the project's own data directory
  explicitly, and add an assertion that the block never fires on a tree whose gates are fresh.
  **Deliberately not fixed in the session that found it**, which had already been told to stop
  opening the next front.

## Declared limits — decided, not pending (2026-09-13)

These are not on the list above because they are not going to be fixed as stated. Each is a
limit we accept, with the reason. Documenting a hole does not close it, so they are written here
as decisions and repeated where the user chooses (`README.md`), never as a quiet pending line.

- **The scope lock watches the edit tools, not the shell.** `hooks.json` registers `scope-lock`
  for `Edit|Write|MultiEdit|NotebookEdit`; a `cat >`, `tee`, `sed -i`, `python -c` or a heredoc
  run through Bash writes without passing it. Why it stays: deciding whether an arbitrary shell
  command writes outside the scope has no exact answer (redirection inside a subshell, an editor
  invoked by a tool, a script that writes later). A guard that fails open on what it cannot parse
  is decoration; one that fails closed denies nearly every command and the plugin becomes
  unusable. **Consequence for the user:** while a scope is declared, write through the edit
  tools; a shell write is not guarded. Partial candidate, explicitly incomplete: deny the known
  write verbs (`>`, `>>`, `tee`, `sed -i`, `cp`, `mv`) against paths outside the scope, and say
  in the denial that the check is best-effort.
- **A changed plugin option does not reach the session that is already open.** Measured
  2026-09-13: the option was correct on disk and the hook honoured it when the variable arrived,
  but the running session kept the value it read at launch. `/reload-plugins` applies it without
  losing the conversation; a new session also does. Why it stays: the reload is the harness's
  own mechanism and works. What changes here: `README.md` says it in the configuration table, so
  nobody concludes the plugin is broken.
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
- **The shell command reader is best effort, and says so in the denial.** `rite-gate` recognises
  `>`, `>>`, `tee`, `cp`, `mv`, `install`, `truncate`, `dd of=` and `sed -i` in command position,
  tracking quote state and `$( )` depth. An interpreter that opens the file itself
  (`python3 -c "open(...)"`, `perl -e`) writes through no verb it can name. This is the partial
  candidate the 2026-09-13 limit above proposed, now shipped; what backs it up is at the CLOSE,
  where `close.sh` refuses a front whose diff touched a file outside the declared globs.
