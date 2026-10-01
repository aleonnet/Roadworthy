# Roadworthy — developer guide

**English** · [Português (Brasil)](README_DEV.pt-BR.md)

For someone who will change the plugin, not use it. Using it is [`README.md`](README.md);
doing one task step by step is [`docs/guides/runbook.md`](docs/guides/runbook.md). This file
explains how the plugin is built and what has to stay true when you change it.

## Start here

You need `bash` (3.2, the one macOS ships, or later), `python3` (standard library only) and
`git`. `shellcheck` and the `claude` CLI are optional: the suite skips what is missing and
says so. There is no build step and nothing to install.

```bash
bash tests/hooks/scope-lock.sh   # one fence, alone, in seconds: read it, it is the pattern
bash tests/run.sh                # the whole gate, the same thing CI runs; takes minutes
claude --plugin-dir .            # a real session with THIS working tree as the plugin
```

Then read one hook from top to bottom — `protect-paths` is short and has the whole pattern —
and `hooks/lib.sh`, which every hook sources. The header of each hook says what it guarantees,
the field case that shaped it and how it was refuted. The detail lives there, not here.

## The idea

A rule written as prose does not hold an agent under pressure; a hook that denies the call
does. Roadworthy wraps a unit of work in a **rite** and makes every step of it a fact on disk:

```
no front --( plan approved in plan mode )--> approval on record
   ^                                               |  scope-write.sh
   |  close.sh: every gate green                   v
   +------------- or close.sh --abandon <----- front open
                                        (.roadworthy/scope, gates, plan.snapshot)
```

- A **front** is one approved plan being executed: its scope (globs), its gates (commands)
  and a snapshot of what was approved, with digests.
- **Hooks** judge against that state the calls that can change something — an edit, a shell
  command, leaving plan mode — and the end of a turn. Each call is a new process: it reads
  the event Claude Code hands it as JSON on stdin, reads the disk, answers and exits. What a
  hook remembers, it remembers in a file.
- **Scripts** are the only writers of what a front IS: its scope, gates, snapshot and state.
  No hook opens or closes a front. A hook only writes down what it saw: a denial, an
  approval, a reviewer's verdict.
- **Skills** and the `cold-reviewer` agent are instructions: they tell the agent which script
  to run. Nothing depends on the agent obeying them; the hooks hold whether it does or not.

Two ideas explain most of the code. **Deny at the door what can be named, and catch the rest
where the set is exact**: a reader of shell commands cannot see what an interpreter writes,
so for an ordinary file the entry gate denies only a target it can name, and the commit
(git's own index) and the closing (the front's diff) refuse what slipped past. **Evidence
has a source that is not the agent**: an approval comes from the person approving the plan
in plan mode, a review from the reviewer's own last line, a gate from the script that ran
it — the last two recorded with the tree they were measured on.

## Code map

**Hooks** — `hooks/`, registered in `hooks/hooks.json`, extensionless on purpose.

- `session-state` — SessionStart; fails open. Says what is on disk. It cannot block.
- `principles` — UserPromptSubmit; fails open. Injects the numbered rules, the reporting form
  agreed for the front and the three-strikes notice; records a person's `rw-human:` answer.
- `rite-gate` — PreToolUse on the edit tools and on Bash; fails closed. The entry gate: no
  front, no write; nothing under `.roadworthy/` by hand; the front on disk is the one that
  was approved; the scope holds through the shell.
- `protect-paths`, `scope-lock` — PreToolUse on the edit tools; fail closed. Protected globs;
  an edit outside the scope.
- `guard-commit`, `overnight-guard` — PreToolUse on Bash; fail closed. What a commit may
  take; what waits for the morning.
- `plan-review-gate` — ExitPlanMode. Before the call it fails closed: it elects the plan
  being submitted and runs the pre-flight or asks for the review. After the call it records
  the approval, and that half fails open; the entry gate can read the same approval from the
  session's transcript.
- `review-record` — SubagentStop; never blocks. Records the cold reviewer's verdict.
- `stop-gate` — Stop; never blocks on its own error. Blocks a finished claim while a gate is
  not fresh. The one hook that answers with exit 2.

**Shared code** — also in `hooks/`.

- `hooks/lib.sh` — sourced by every hook: parses the event once, `deny` and the denials
  ledger, the crash policy, which repository a path belongs to, the owner's lists.
- `hooks/run-hook.cmd` — the launcher `hooks.json` calls; a batch and shell polyglot.
- `hooks/shellread.py` — reads a shell command the way the shell does and says what it
  writes and removes. The largest file here; its contract is a table of cases.
- `hooks/globmatch.py` — the glob grammar.
- `hooks/planblocks.py` — what a plan declares (scope, gates, base), its fingerprint, and
  whether an approval of that fingerprint is on record.
- `hooks/frontcheck.py` — is the open front intact, what changed outside its scope, whose
  commit is it, what would this commit take.

**Scripts** — `skills/<skill>/scripts/`, the hands of the rite.

- plan: `scope-write.sh` opens a front; `plan-preflight.sh` checks a plan mechanically.
- close: `close.sh` runs the gates, records the evidence, derives the state and releases
  the scope; `tree-fingerprint.sh` names the tree a gate was measured on; `close-front.sh`
  moves the documents of a closed front into history.
- document: `docs-init.sh`, `docs-check.sh`, `pointers-check.sh`.
- refute: `refute.sh` plants a defect and restores by hash; `refute-ledger.sh` refuses a
  fence with no refutation on record.
- resume: `resume-pick.sh`. overnight: `overnight-start.sh`, `overnight-entry.sh`,
  `overnight-close.sh`.
- `bin/rw-metrics` turns an eval run into numbers.

**State on disk** — `.roadworthy/`, in the project being worked on.

- From `scope-write.sh`: `scope` and `plan.snapshot` (local), `gates` (tracked: it is
  committed with the front).
- From `close.sh`: `state`, and in `evidence.jsonl` each gate it ran, each human
  verification and how each closing ended. Hooks append approvals and reviewers' verdicts
  to the same ledger.
- Other ledgers: `denials.jsonl`, `refutations.jsonl`, `preflight.jsonl`; `stop-latch/`; the
  night marker `overnight`.
- The owner's, never the agent's: `protected`, `free`, `rites`, `overnight-rules`,
  `docs.json`.

**Tests** — `tests/`, from narrow to wide.

1. Cases: `tests/hooks/`, `tests/scripts/`, `tests/meta/`. One file per fence or script; a
   synthetic event goes in and the answer is judged. `tests/cases.txt` is the manifest.
2. The simulator, `tests/sim/rite-sim.py`: whole sessions through every registered hook,
   each call executed in a toy repository when no hook denies it.
3. `tests/attack.sh`: tries to get PAST the fences. Each attack is `refused` or `declared`.
4. `tests/bench/bench.sh`: a real headless session. It costs money and is not in the gate.
5. `evals/`: the same prompts with and without the plugin; see `evals/README.md`.

## Invariants

Most of them are an absence, which is why they are hard to see from any one file.

1. **No guard fails open.** Every hook declares `RW_ON_CRASH` before it sources
   `hooks/lib.sh`. With `deny`, an internal error and an early exit of the script — an unbound
   variable, a line the shell cannot parse — answer with a denial. A hook with no declared
   policy is itself an error.
2. **A denial is JSON on stdout with exit 0.** Among the hooks only `stop-gate` exits 2,
   because that is how a Stop hook blocks. `principles` never may: it would erase the prompt.
3. **A project's evidence never goes to `CLAUDE_PLUGIN_DATA`.** It resolves through
   `rw_data_dir`: `ROADWORTHY_DATA` when set, else the project's `.roadworthy/`. That other
   variable is shared by every project on the machine and absent from a person's shell.
4. **One grammar each; do not add a copy.** Globs, shell commands, plan blocks and "whose
   change is it" each have one file in the shared code above. Older readers still stand
   beside them and are not a pattern: `overnight-guard` and parts of `guard-commit` match the
   raw command text; `plan-preflight.sh` and `plan-review-gate` read parts of a plan themselves.
5. **The repository that judges a file is the one the file is in** (`rw_target_root`). Only
   a file in no repository at all falls back to the one the session stands in.
6. **The agent writes nothing under `.roadworthy/` by hand.** Scope, gates and snapshot come
   from `scope-write.sh`; the state and the gate records from `close.sh`; what a hook
   witnessed, from that hook; the owner's files from the owner (`docs-init.sh` creates
   `docs.json` when it is missing).
7. **A person's act is never typed by the agent.** Opening a front as the owner (`--owner`)
   and answering a human verification are denied to it.
8. **The closing measures what was approved**: a front the rite opened closes only when its
   scope and gates still match the digests in the snapshot, and every declared gate runs or
   the closing refuses.
9. **No case outside the manifest, no case that ends early.** `tests/run.sh` refuses when
   `tests/cases.txt` and the directories disagree, and a case that never reaches `rw_end`
   is red whatever its exit status.
10. **Nothing local is tracked**: no local-state file and no home path in what git tracks
    (`tests/meta/privacy.sh`).

## Cross-cutting concerns

- **How a hook dies.** Claude Code treats a non-zero exit code other than 2 as a
  non-blocking error and lets the call through, so `hooks/lib.sh` watches the ERR trap
  (with `errtrace`, or it is absent inside functions) and the EXIT too. A command whose
  non-zero exit is an
  ANSWER (`close.sh --check`, the pre-flight) is called inside an `if`, with
  `set +o errtrace` around it: copy the pattern from `stop-gate`.
- **Time.** Each hook has a `timeout` in `hooks/hooks.json`, and a hook that runs out of
  time does not deny. Work that costs per path is capped or done in one process, and every
  tool call pays for every hook registered on it: the event is parsed once per call.
- **bash 3.2.** No `wait -n`. A `case` inside `$( )` does not parse. An unpaired apostrophe
  in a heredoc inside `$( )` breaks the file far from the cause; `bash -n` in
  `tests/meta/hygiene.sh` catches it. In a case, which runs under `set -euo pipefail`, an
  abort on an unbound variable reaches the EXIT trap with status 0: hence `rw_end`. A hook
  runs under `set -u` alone, and there the trap sees the failure.
- **Python inside the shell.** Most of the logic is Python in heredocs.
  `tests/meta/hygiene.sh` compiles the blocks its pattern finds and fails on an import
  nobody uses; a heredoc whose opening line carries anything after the tag is not found.
  Keep bytecode out of the tree: `sys.dont_write_bytecode`.
- **Paths.** macOS hands a hook `/var/...` while git answers `/private/var/...`: resolve
  both sides with `rw_realpath` before comparing. A glob is anchored at the repository root.
- **The list of local-state files is spelled out in many files**: hooks, scripts, the eval
  instrument, the ignore file, several cases and the simulator.
  `git grep -l 'refutations' -- hooks skills bin tests .gitignore` lists the files that
  name one of them; open each, and add a new state file wherever there is a list.
- **Options and requirements.** A user option is `userConfig` in
  `.claude-plugin/plugin.json`, reaches a hook as `CLAUDE_PLUGIN_OPTION_<KEY>` and is read
  with `rw_option`; a session already open keeps the old value until `/reload-plugins`. What
  a project demands lives in its own `.roadworthy/rites`, read with `rw_rite`.
- **Windows.** `hooks/run-hook.cmd` hands the hook to Git Bash. With no bash it refuses:
  exit 2 for a guard, exit 1 for the four hooks that must not block. That branch runs only
  in CI (`.github/workflows/ci.yml`, job `windows-no-bash`).
- **Two languages.** Plans, reviews and status words are read in English and in Portuguese
  (`Scope` or `Escopo`, `VERDICT` or `VEREDITO`), and `README.md` has a Portuguese twin
  kept in step by a gate — as this file has its own.

## Changing things

Every change to this repository goes through the plugin's own rite — plan, approval, front,
closing — and the runbook has the steps. What to touch together:

- **A hook's behaviour.** First the assertion that fails, in its case under `tests/hooks/`.
  Then the hook. Refute the new check once with `refute.sh` and write the dated `Refuted`
  line in the hook's header: a gate reads it. If the change closes a way round, add the
  attack to `tests/attack.sh`; if it changes a guarantee, both READMEs and the CHANGELOG.
- **A new hook.** An extensionless file in `hooks/` that exports `RW_HOOK` and
  `RW_ON_CRASH`, sources `hooks/lib.sh` and calls `rw_read_event`; an entry with a `timeout`
  in `hooks/hooks.json`; a case, and its line in `tests/cases.txt`; its name in `RW_FENCES`
  (`tests/meta/hygiene.sh`), in the `--sources` of the refutation-ledger gate, in the
  no-bash branch of `hooks/run-hook.cmd` if it must not block, in both READMEs, and in the
  code map above — a gate refuses a hook or a script this file does not name.
- **A new option.** `userConfig` in `.claude-plugin/plugin.json`, `rw_option KEY default` in
  the hook, the configuration table of both READMEs, and a case in both directions.
- **A command the reader misreads.** A row in the table of `tests/scripts/shellread.sh`
  first — the table is the reader's contract — then `hooks/shellread.py`.
- **A new case.** A file that sources `tests/lib.sh`, builds its own fixtures
  (`tests/fixtures/`) and ends with `rw_end`, plus its line in `tests/cases.txt`. Capture
  output into a variable before matching it: under `pipefail`, `cmd | grep -q` goes red
  when the producer writes anything after the match.
- **A new scenario.** A JSON file in `tests/sim/scenarios/`: `live-*` for honest work, where
  a denied step is a dead end; `att-*` for an attempt to get past the rite.
- **Refutation is once per guarantee, when it is born.** The suite carries it afterwards.
- **A release.** The two manifests and the CHANGELOG move together, and a gate checks it.

## Where to read next

- `README.md` — what each hook guarantees, every option, the declared limits. It is the
  reference; this file points to it instead of repeating it.
- `docs/README.md` — the map of `docs/`. The records in `docs/decisions/` say why things are
  the way they are, each with the measurement behind it.
- `docs/reference/roadmap.md` — done, pending, and the limits accepted on purpose. Read
  "Declared limits" before fixing one.
- `docs/guides/runbook.md` — how to do each recurring task, and what to do when it fails.
- Claude Code's own documentation, for what a hook receives and what its exit codes mean:
  <https://code.claude.com/docs/en/hooks> and <https://code.claude.com/docs/en/plugins/create>.

The shape of this file is the one matklad describes for an `ARCHITECTURE.md` — short, a code
map, invariants, cross-cutting concerns, names instead of links
(<https://matklad.github.io/2021/02/06/ARCHITECTURE.md.html>) — and the runbook is a how-to
guide in the sense of Diátaxis (<https://diataxis.fr/how-to-guides/>).
