# Roadmap

Living document (undated name by design). One line per item, with the measured reason.

## Done
- 0.1 hooks and skills; 0.2 documentation tree by role, evidence-gated close, refutation
  ledger, resume by name; 0.2.1 per-project status vocabulary (found by adopting on a
  Portuguese-language monorepo).
- Evals suite (`evals/`, six cases) and `bin/rw-metrics` (seven KPIs from the eval JSON, the
  run trace and the kept workspace).
- 0.3.0 overnight mode: `/roadworthy:overnight`, `overnight-guard`, `freeze:` in `protect-paths`,
  the Overnight policy section, the `overnight` eval (record `docs/decisions/2026-09-03-1322-overnight-mode.md`).

## Pending
- **Bash-granting evals on macOS with Docker Desktop.** `claude plugin eval --allow-tools Bash`
  refuses to run when the Docker credential store contains symbolic links (Docker Desktop
  keeps its CLI plugins as links under `~/.docker/cli-plugins`); `DOCKER_CONFIG` does not
  bypass the check because both locations are inspected. Consequence: the `commit` (forbidden
  flag, empty staging) and `refute` cases cannot run locally; both guards are covered by the
  unit gate (`tests/run.sh`), not by the experiment. Plan: run those two cases in CI on a
  Linux runner, where the store is a plain directory.
- `hooks/stop-gate` (Stop): block the turn while `close.sh --check` reports STALE or MISSING
  gates; opt-in (`stop_gate`), fails open.
- `/mutate` with `scripts/mutate-baseline.sh`: read the report of the language's mutation
  tool and print the measured score as the suggested threshold.
- Denials log: `deny()` appends `{ts, hook, reason, cwd}` to `denials.jsonl` so the
  guardrail count is readable without the eval trace.
- **Scope widening made visible.** The scope lock lets the agent edit `.roadworthy/scope`
  by design; in the with-and-without experiment (2026-09-02) one run crossed the scope that way
  after three denials. Record widenings (`{ts, before, after, cwd}` in `denials.jsonl` or a
  sibling ledger) so `close.sh --check` and `rw-metrics` print "scope widened during the task".
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
  "work is under way and no skill has fired". Candidate: a Stop or PreToolUse signal when the
  session has edits but no skill invocation and no `.roadworthy/scope` — fails open, opt-in,
  like `stop-gate`.
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
- **`.roadworthy/gates` is required by close and created by nobody.** `close.sh` reads the gate
  commands from `.roadworthy/gates`; the file does not exist in a project that has been under the
  plugin for two weeks, and no hook or skill warns about its absence. Measured: absent in
  `blebridge-175` at 2026-09-08. Candidate: `plan` writes it from the plan's Verification section,
  the same way it writes `scope`.
- **The scope file has no machine-readable link to the plan that justified each line.** It grew
  four ad-hoc widenings with prose comments in one project. Nothing ties a glob to the plan that
  introduced it, so `close` cannot tell which lines to retire when a front ends. Candidate: one
  `# plan: <file>` header per block, and `close` removes only the blocks of the plan it closes.

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
