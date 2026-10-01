# Runbook

How to do the recurring tasks on this repository, and what to do when one goes wrong. It
assumes [`README_DEV.md`](../../README_DEV.md): read that first for how the plugin is built.

Each entry says when you need it, what to run, what you should see, and what to do if you do
not. Commands run from the repository root unless the entry says otherwise; `<...>` is yours
to fill. `T` stands for the repository a hook call is about: `T=/path/to/some/repo`.

## Run the working tree in a real session

When you changed a hook or a skill and want to see it answer a real tool call.

```bash
claude plugin validate . --strict     # the manifests and every skill and agent file
claude --plugin-dir . plugin list     # is this tree loaded?
claude --plugin-dir .                 # a session with this tree as the plugin
```

Expect `✔ Validation passed`, and in the list, under "Session-only plugins", the entry
`roadworthy@inline` with `Status: ✔ loaded` and the path of this checkout. After editing a
file during the session, run `/reload-plugins`.

If the plugin is also installed, the list shows both `roadworthy@roadworthy` and
`roadworthy@inline`. When it matters which copy answered, turn the installed one off for the
duration (`claude plugin disable roadworthy@roadworthy`, then `enable`).

## Run the tests

```bash
bash tests/hooks/scope-lock.sh                         # one case, in seconds
bash tests/run.sh                                      # the whole gate; RW_JOBS=1 for serial
bash tests/attack.sh                                   # the cheating suite alone
RW_SIM_ONLY=live-01 bash tests/meta/rite-liveness.sh   # one simulated session
python3 tests/sim/rite-sim.py tests/sim/scenarios/live-01-work-inside-an-open-front.json
bash tests/bench/bench.sh                              # a REAL session; spends a few cents
```

Expect `[OK]` lines and exit 0 from a case; `RESULT: gate clean` from the gate;
`RESULT: every cheat refused, every pass declared` from the attacks; `RESULT: held` from the
simulator, with one line per step; `RESULT: the fences hold in a real session` from the bench.

If not:

- `[CASE RED] <file>`: run that file alone and read its `[FAIL]` lines.
- `[CASE DIED]`: the case stopped before `rw_end` — an unbound variable or a failed command,
  not an assertion.
- `the case manifest and the case files disagree`: add or remove the line in
  `tests/cases.txt`.
- `[PASSED] ... an attack got through and is not declared`: a fence regressed, or a new limit
  has to be declared with its reason. `[GREW]`: a declared attack is refused now; promote it.

## Work on this repository through its own rite

With the plugin installed, a write to this repository's files is denied until a front is
open; the plan itself is the exception. The steps:

1. Write the plan as a `.md` directly in `docs/plans/` — that needs no front — from
   `skills/plan/templates/plan.md`. `Scope` and `Verification` are fenced blocks. Copy the
   Verification block of the newest plan in `docs/plans/done/`: it is this repository's
   quality bar. Add your own gates under it.
2. Check it: `bash skills/plan/scripts/plan-preflight.sh docs/plans/<plan>.md --transcript
   <the session's transcript>` must end with `plan-preflight: green`.
3. Submit it in plan mode and approve it there.
4. Open the front: `bash skills/plan/scripts/scope-write.sh docs/plans/<plan>.md`.
5. Work and commit. The opening rewrote `.roadworthy/gates`, which is tracked: commit it
   with the front, or the closing calls the tree dirty.
6. Write the hand-off (a `.md` in `docs/plans/`) and commit it BEFORE closing.
7. Close: `bash skills/close/scripts/close.sh`.

Expect, at step 4, `scope-write: front open from <plan>` followed by the base, the number of
globs and of gates; at step 7, one `OK` line per gate and
`close: passed — evidence in <ledger>; scope released`.

Working by hand, outside an agent, the owner opens the front with no approval on record:
`scope-write.sh docs/plans/<plan>.md --owner`. An agent that types `--owner` is denied.

If the plan has to change while the front is open — a file the scope did not name, another
gate — edit its Scope or Verification block, approve it again in plan mode, and run
`scope-write.sh` on the same plan: it says `front reopened` and keeps the base.

## The closing refuses

`bash skills/close/scripts/close.sh --check` says where each gate stands for the tree in front
of you: `FRESH` (ran green on this tree), `FRESH-RED` (ran red on this tree), `STALE` (ran on
another tree), `MISSING` (never ran). `close.sh --state` prints `passed`, `gaps_found`,
`needs_human` or `none`.

- `close: the tree is dirty; commit first`: commit. What is not this front's is set aside
  with `git stash push -u -- <path>` and brought back after the closing.
- `close: gaps_found — N gate(s) red; scope kept`: the `FAIL` line names the gate and shows
  the end of its output. Fix, commit, close again.
- `close: the front touched N file(s) outside its declared scope`: put those files back as
  they were at the base, or take the change to the plan as in the entry above.
- `close: no front is open here — the last one (...) already ended as 'passed'`: something
  was committed after the closing, usually the hand-off. Reopen from the same plan and close.
- No way forward at all: `close.sh --abandon "<reason>"` prints `close: front abandoned`,
  records the reason, leaves the state at `gaps_found` and releases the scope.

## "not the front that was approved"

Writes are denied with `the front open in <repo> is not the front that was approved:
<reason>`, and the reason says which of three things happened. The snapshot is gone or cannot
be read. Or the scope, the gates or the snapshot no longer match what was recorded when the
front opened — a hand edit, a stash or a checkout that brought an old `.roadworthy/gates`
back. Or `no approval is on record` — the front was opened from a plan nobody approved, or in
a clone, a worktree or a ledger that never saw the approval.

Three ways out, and the denial names them: reopen from the plan with `scope-write.sh` (open
to an agent only when an approval of what the plan declares now is on record); the owner
reopens with `--owner`; or `close.sh --abandon "<reason>"`.

## A turn is blocked at its end

The stop gate answers `the turn says the work is finished, and the declared gates are not`,
followed by the output of `close.sh --check` for each repository the turn wrote in.

Either close the front (the entries above), or end the turn saying plainly what is left: a
message that names an open item is a status report and is not judged. The same claim on the
same tree is not blocked twice, so a second attempt passes — which is the latch working, not
the gates being fresh.

If an honest message was blocked, the words that count as a claim are in `claims_done`, in
the stop gate's own file, and the marks that make a message a status report are the option
`stop_gate_open_markers`.

## A check only a person can make

```bash
bash skills/close/scripts/close.sh --needs-human "<what has to be looked at>"
bash skills/close/scripts/close.sh --human          # what is waiting, with an id each
```

Expect `close: needs_human — <item>`, and from then on `close.sh --state` says `needs_human`
whatever closes afterwards, until a person answers. The person answers in their own prompt,
with a line of their own:

```
rw-human: all approved
rw-human: <item or id> rejected <note>
```

or, in a shell outside the agent, `close.sh --human "<item>|<id>|all" approved|rejected --by
<who>`. The agent typing that command is denied: `a human verification is answered by the
person, not by the agent`.

## A hook denies everything, or errors

Reproduce the one call by hand. A hook reads the event as JSON on stdin and answers on stdout:

```bash
printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/src/a.py"}}' "$T" "$T" \
  | bash hooks/run-hook.cmd rite-gate
RW_CMD='cp src/a.py out/b.py && rm -rf build' python3 hooks/shellread.py "$T"
printf '{"hook_event_name":"SessionStart","source":"startup","cwd":"%s"}' "$T" \
  | bash hooks/run-hook.cmd session-state
```

Expect, from a guard, one of three answers: nothing at all (the call passes); one line of
JSON whose `permissionDecision` is `deny`, with the reason; or JSON that carries only an
`additionalContext` (the call passes and the agent is told something). From the reader, one
line per target — kind, directory, path, where `W` is a write and `R` a removal (the header
of the file lists the rest). From the last one, the state a session is told when it starts.
When there is an answer, `| python3 -m json.tool` makes it readable; on an empty answer that
tool prints an error of its own, which says nothing about the hook.

- `internal error at line N; failing closed`: the hook itself broke. `bash -n hooks/<hook>`,
  then its case under `tests/hooks/`. A guard that breaks denies; that is by design.
- `the event handed to the hook is not JSON`, or `could not be read`: the input was at fault,
  not the hook. By hand, it is usually the quoting of the `printf` above.
- The same denial three times: the third says so. It is the front telling you the act is not
  what was approved, not an obstacle to route around.
- An option you changed has no effect: the session read it at start. `/reload-plugins`.
- For what Claude Code itself did with a hook — which matched, its exit code, its stderr —
  read its debug log: <https://code.claude.com/docs/en/hooks>.

## Read the ledgers

Reading anything under `.roadworthy/` is open to everyone. Writing is not: the front's files
and the ledgers are written by the rite's scripts and hooks, the owner's files by the owner.

```bash
python3 -c 'import json
for r in map(json.loads, open(".roadworthy/denials.jsonl")):
    print(r["ts"], r["hook"], r["reason"][:90])'
python3 -c 'import json
for r in map(json.loads, open(".roadworthy/evidence.jsonl")):
    print(r["ts"], r.get("kind", "gate"), r["cmd"][:60], r["exit"])'
```

Expect one line per denial (when, which hook, why), and one per piece of evidence: a `gate`
with its command and exit status, an `approval`, a `review`, a `needs-human`, a `human`
answer, a `close` with how the closing ended.

## Prove a new check can fail

Once, when the check is born. From the root of the repository the file under test is in:

```bash
bash skills/refute/scripts/refute.sh --file <file under test> --sed '<s/right/wrong/>' \
  --expect '<the failure text the check must print>' -- bash tests/hooks/<case>.sh
```

Expect `refute: OK — red with the defect ('<text>', exit N), green on the clean file, <file>
restored (hash verified)`, and a record in `.roadworthy/refutations.jsonl`. Then write the
dated `Refuted` line in the header of the file.

If it says the check `stayed green with the defect`, the check cannot catch it. If it went
`red, but not for the intended reason`, either the expectation or the check is wrong. If it
is `also red on the clean file`, the check was broken before the injection.

## Release a version

1. A front as above, whose scope names the two manifests, the CHANGELOG and both READMEs.
2. The same `version` in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`;
   in the CHANGELOG, a `## [x.y.z] - YYYY-MM-DD` heading under an empty `[Unreleased]`. A gate
   refuses when the three disagree.
3. Run the bench once and paste its result into the hand-off.
4. Close, then push, then:

```bash
gh run list --limit 3                           # the run of the push
claude plugin update roadworthy@roadworthy
claude plugin details roadworthy@roadworthy     # version, hook events, token cost
```

Expect the run `completed  success`, and the new version in the details. Sessions already
open need `/reload-plugins`.

## CI is red

```bash
gh run list --limit 3
gh run view <run id> --log-failed
```

Three jobs run on a push: the gate on Linux, the gate on macOS, and the launcher on Windows
with every bash hidden. The two gates differ in the shell — macOS runs bash 3.2, Linux a
later one — so a case green here and red there is usually a shell behaviour assumed instead
of measured. The Windows job calls four hooks by name and reads their exit codes; a new hook
is not exercised there until you add it to the job, next to its line in the launcher.

## Turn a fence off

The owner's decision, never the agent's. `/plugin`, Roadworthy, Configure, then
`/reload-plugins`: `rite_gate`, `scope_lock`, `stop_gate`, `commit_scope`,
`plan_review_required` and `session_state` each switch one guarantee off; the README has the
whole table. To ask MORE of one project instead, the owner writes `.roadworthy/rites` in it.

## The night marker was left on

A session starts with `overnight  ON since ...` in its state, and a push answers `overnight
mode is on`.

```bash
bash skills/overnight/scripts/overnight-close.sh --run
```

Expect the gates to run, then `overnight-close: off at <time> — hand-off <file>`; commit the
hand-off it wrote. If it refuses, it names why: a dirty tree, a gate that is not fresh, a
plan that changed during the night. When the night is simply to be dropped, removing the
marker is the owner's act, in a shell outside the agent: `rm .roadworthy/overnight`.
