# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

## [Unreleased]

## [0.6.1] - 2026-09-14

**The plugin, complete, measured against its own claims.** Every one of the 172 tracked files was read
whole before this release was planned, and what the reading found was measured in the act: a chain
that let a front close `passed` after a write outside its scope, a hook environment that sent the
evidence of a project to a directory shared by every project, an accepted decision record promising
a mechanism the code did not have, and four claims in this very file (0.6.0) that the files did not
sustain. Each is closed below, each refuted with the defect planted (28 refutation records written
by `refute.sh` in this front), and the two things the suite cannot fake are measured for real: a
headless session on the working tree (`tests/bench/bench.sh`) and the evals with a smaller model.

**Behaviour changes to know about before upgrading.** Four, each taken deliberately:
1. **`.roadworthy/protected` and `.roadworthy/overnight-rules` are the owner's.** The agent cannot
   edit or remove them through the edit tools or the shell. They are what `protect-paths` and the
   night read to guard against the agent; a fence whose input the guarded party edits is not a
   fence. Acceptance 7 of the 0.6.0 plan allowed it and is reversed. `docs.json` stays editable.
2. **Removing is writing.** `rm`, `unlink`, `rmdir`, `git rm` and the SOURCE of `mv` are targets of
   the entry gate: nothing under `.roadworthy/` may be removed by hand, and removing an ordinary
   file inside the repository needs an open front like writing one does.
3. **Project evidence lives in the project.** The denials ledger, the evidence ledger, the stop
   latch, the refutation and pre-flight records resolve to `ROADWORTHY_DATA` when it is set and to
   `<repository>/.roadworthy` otherwise. `CLAUDE_PLUGIN_DATA` is out of that chain: Claude Code sets
   it for every hook to a directory per plugin, shared by every project (`~/.claude/plugins/data/<id>/`),
   and a person's shell does not set it at all. Measured on 2026-09-14 at 13:33: six FRESH gates
   reported MISSING by the stop gate, the denials of the day in the shared directory, the line
   "a fence has denied three times" never once reaching a prompt. Anyone who relied on the shared
   directory should point `ROADWORTHY_DATA` at it. The pin of the principles file stays there on
   purpose: it is global by construction.
4. **`hooks/run-hook.cmd` on Windows without bash refuses.** 0.6.0 said it did; the file exited 0
   in silence. Now a guard fails closed (exit 2, reason on stderr) and `principles` / `stop-gate`
   warn with exit 1, because exit 2 there erases the prompt or traps the session. The WSL launcher
   in `System32` is not treated as a bash. Executed on a Windows runner in CI (`windows-no-bash`).

### Fixed — 2026-09-14, the chain that closed a front `passed` around its own scope
- **`rite-gate`** reads removals (`rm`, `unlink`, `rmdir`, `git rm`, the source of `mv`), denies them
  anywhere under `.roadworthy/`, and denies the owner's two files through both doors. `find -delete`,
  `xargs rm` and interpreters that unlink are declared in `tests/attack.sh` like the interpreters
  that write; what backs them up is the closing.
- **`close.sh`** refuses, in the closing and in `--check`, a scope the rite wrote whose
  `plan.snapshot` is gone: the snapshot is what the closing measures against, and its removal used
  to send the closing down the pre-0.6.0 path that skips the digests and the out-of-scope check. A
  scope written by hand (toy repositories, evaluation scaffolds, older projects) has no banner and
  keeps the old path, so no agent meets a wall it cannot resolve.
- **`close.sh`** no longer counts the front's own plan as a stray file when the plan lives inside
  the repository (the `plans` directory of `docs.json`): it is written before the front exists and
  cannot be in its own scope.
- **`tests/attack.sh`** grew from 37 attacks (32 refused, 5 declared) to 64 (50 refused, 14
  declared), with its first attacks on scripts and on the Stop hook, and every contour known on
  2026-09-14 is in it as refused or declared with the reason.

### Fixed — 2026-09-14, evidence looked for in the wrong directory
- One resolver, `rw_data_dir` in `hooks/lib.sh`, for the denials ledger (writer and reader), the
  stop gate (which now passes it to `close.sh --check` explicitly), `close.sh`, `plan-preflight.sh`
  and `refute.sh`. Reproducers in the suite run the hooks the way the harness runs them, with only
  `CLAUDE_PLUGIN_DATA` set; both were red before the fix.
- **`stop-gate`** honours `stop_hook_active`. The hooks guide documents it ("Claude Code overrides a
  Stop hook after it blocks eight times in a row without progress … Parse the `stop_hook_active`
  field"); a comment in the hook said the field was undocumented, and it was not.

### Fixed — 2026-09-14, what a plan is, and where
- **`plan-review-gate`** elects, when the call carries no plan text that matches a file byte for
  byte, the plan this session last wrote in a plans directory (from the transcript the harness
  keeps), and only then the newest by date — saying so in the `additionalContext` it returns
  instead of choosing in silence. Acceptance 16 and 17 of the 0.6.0 plan, promised by
  `docs/decisions/2026-09-14-0239-four-accepted-claims-refuted.md` and measured absent.
- **The plan has two homes**, and the gate, the entry gate and the scope lock read both: `plans_dir`
  (plan mode) and the `plans` directory the project declares in `.roadworthy/docs.json` (the house
  norm). A plan written in the second got "no plan found" in the field on 2026-09-08.
- **One glob grammar**, `hooks/globmatch.py`, read by `lib.sh`, `close.sh` and `bin/rw-metrics`.
  `rw-metrics` answered through `fnmatch` first, where `*` crosses a `/`, so `app/*.py` meant one
  thing to the lock that denied an edit and another to the instrument counting it out of scope;
  `tests/scripts/globmatch.sh` puts the three entry points to one table. The roadmap named
  `docs-check.sh` as one of the three; read whole, it has no glob matcher.

### Fixed — 2026-09-14, four claims of this file that the files did not sustain
- "`run-hook.cmd` … warns and refuses" (0.6.0, behaviour change 5 and its Fixed entry): the file
  exited 0. Fixed above, and executed in CI.
- "The suite now compiles every Python script in the plugin and fails naming any import nobody
  uses" (0.6.0): nothing in the suite did either. `tests/meta/hygiene.sh` now compiles every
  `python3 - <<'PY'` block in the fences and scripts plus the standalone files, and names every
  dead import — and found two on its first run (`sys` in `hooks/rite-gate`, `re` in
  `scope-write.sh`), both removed.
- The suite described itself as 0.6.1 in `tests/lib.sh` and `tests/run.sh` while the reorganisation
  it describes shipped in 0.6.0 (`a076e99`); the two comments say 0.6.0.
- The section "the entry gate met a real session and was unusable" was written under `[0.6.0]`
  after 0.6.0 had been published (`f51ad92`). It belongs here and is moved here.

### Fixed — 2026-09-14, the entry gate met a real session and was unusable

0.6.0 was installed and reloaded at 11:45. **That is the first time `rite-gate` ever ran outside a
synthetic event in a toy repository** — the acceptance 0.5.0 left unproved. It fired, and the bench
found two defects in two minutes, each with the command that produced it.

- **A shell write outside the repository was denied.** `echo x > /tmp/f` from a project with no
  front open came back refused, and so did every write into the session's scratchpad. The gate
  exists to stop work on THIS repository without a rite; a write somewhere else is not that. The
  same omission was in the edit branch. Both now ignore a target outside the repository root, and
  the foundation is still matched by its path relative to that root, which is where it lives.
  - This also answers `2>/dev/null`, the commonest idiom in shell, which was being read as a write
    to `/dev/null` and denied. A list of device names was written first and then **removed**: the
    refutation proved it was dead code, because /dev/null is not inside the repository either.
- **The plan could not be written through the shell.** The edit tools were exempt in `plans_dir`;
  the shell was not, so `cat > <plan>` was refused — and the plan is what OPENS a front, so the
  first front of a project could only be opened with an edit tool. With the default plans_dir the
  rule above already covers it; the exemption is what makes it hold for a project that keeps its
  plans inside the repository, and that is the case the assertion measures.

Each fix is refuted against `tests/hooks/rite-gate.sh`: the defect injected, the case red for its
own reason, green again on the clean file, the file restored with its SHA-256 verified.

### Changed — 2026-09-14, the evals judge state, never the attempt
- Twelve graders across `evals/` and `evals-round2/` were `tool_used` (counting the ATTEMPT, so an
  edit a fence denied scored against the arm that denied it), matched a word that was already in
  the prompt, or accepted every outcome. All judge the bytes of a file or the final `STATUS:` line
  now, which is the rule `evals/README.md` always stated. The `scope` case expects
  `STATUS: needs_human`: without commands there is no verification of one's own.
- `allowed_tools` in a case and `--allow-tools` on the command line are not in contradiction: the
  documentation says the two add up ("plus whatever you grant with `--allow-tools`, which applies to
  every case in the run"). The READMEs say so with the citation.
- Measured with `--model haiku`, both rounds, three runs, with and without the plugin; the numbers,
  the commands and the cost are in `docs/decisions/2026-09-14-1610-evals-com-modelo-menor.md`.
  `--allow-tools Bash` is still refused on this machine, with the harness's own words recorded
  there; the `overnight` case runs in the `evals-bash` job of the CI.

### Added — 2026-09-14
- `tests/bench/bench.sh`: the fences met by a real session, headless, driven by the script
  (`claude -p --plugin-dir <this repository> --output-format stream-json`), one exact act per prompt,
  judged on the harness's `permission_denials` and on the disk. The seven-step bench of 0.5.0 that
  needed a person in plan mode never got filled; this one fills itself.
- `.github/workflows/ci.yml`: `windows-no-bash` (executes the no-bash branch of `run-hook.cmd` on a
  Windows runner with every bash hidden) and `evals-bash` (the `overnight` case on Linux, started
  by hand, skipped without the secret).
- `bin/rw-metrics` no longer returns a flag nobody read.

## [0.6.0] - 2026-09-14

**The rite stops being optional.** Measured on this repository on 2026-09-13, against the session
that was repairing the plugin: 60 edits, 117 shell commands, **zero** rite invocations, with the
plugin installed and active, and nothing noticed by anyone. Every fence was working; the front was
simply never opened, and a fence that only guards a front nobody opens guards nothing. `rite-gate`
is the wall for that, on the edit tools **and on Bash**, which is where 117 of those 177 acts went.

**What guards a plan changes.** Five rounds of cold review on one plan never converged here, and
the measured cause was not the reviewer: every round was spending its attention on things a machine
can check. `plan-preflight.sh` checks them — citations by content, scope paths, acceptance
numbering, declared corrections, impact-sweep commands, and whole-file reading proved from the
session transcript — and the cold reader goes back to the **diff**, which is what principle 4 of
this plugin always said. The option is `plan_gate` (`preflight` | `review` | `both`), born in
`preflight`.

**Behaviour changes to know about before upgrading.** Five, each taken deliberately:
1. A glob in the scope is anchored at the root. `README.md` no longer also matches
   `docs/README.md` — the old behaviour came from stripping the anchor and re-anchoring at any
   slash, and it was a defect, not a contract.
2. The scope lock and the protected list now resolve the repository root, so they apply in
   subdirectories. They used to be **inert** outside the root.
3. `rite-gate` **denies** where the roadmap had planned to fail open. Failing open was measured as
   equivalent to not existing. The `rite_gate` option is there for anyone who disagrees.
4. Submitting a plan depends on the pre-flight, not on a verdict (`plan_gate`, above).
5. `hooks/run-hook.cmd` no longer exits 0 when it cannot find bash on Windows. It prints a warning
   and refuses. Anyone on Windows without bash has been running with **no guardrails at all**
   while believing otherwise; discovering that through a refusal is better than not discovering it.

### Fixed — 2026-09-14, the suite reported success on a suite that had died

Found by the suite, on itself, while it was being reorganised — and it is the worst class of defect
this project can have, because it is the instrument that proves everything else.

- **An aborted run exited 0.** `tests/run.sh` ended with `trap 'rm -rf "$TMP"' EXIT`. The handler's
  last command is the `rm`, and its status becomes the script's, so any abort that was not an
  assertion — an unbound variable, a `set -e` failure outside a `||` — left the gate **green** with
  half of it never run. Reproduced in three lines. Carrying `$?` out of the handler is not enough
  either: measured on bash 3.2, an unbound variable under `set -u` makes the `EXIT` trap see
  `$?=0`, while an ordinary `set -e` failure correctly shows 1. What fixes it is a flag — `rw_end`
  is the only thing that sets it and it is the last line of every case, so a case that did not
  reach the end is red whatever the shell decided the status was. `tests/meta/runner.sh` measures
  that in both directions, including the discriminator that the same abort without the flag does
  return 0.

### Changed — 2026-09-14, the suite becomes cases and fixtures

`tests/run.sh` was 1407 lines and 36 sections in one shell, and `tests/fixtures/` and `tests/hooks/`
had been empty since 2 September — untracked, since git does not version an empty directory, so
nobody who cloned the repository ever received them.

- **One case per fence and per script**, in `tests/hooks/`, `tests/scripts/` and `tests/meta/`, each
  runnable alone: `bash tests/hooks/scope-lock.sh`. The measured reason is not tidiness. A
  refutation runs its check twice, so against the monolith every refutation cost two full suite
  runs — the six refutations of `plan-preflight.sh` took 32 minutes of wall clock. Against one
  case: **5.3 seconds**.
- **`tests/cases.txt` is the manifest, and it is a fence.** A runner that globs a directory loses a
  case in silence the day someone deletes the file. This one refuses to run when the list and the
  directory disagree, in either direction, and names what is missing on which side.
- **Eight variables crossed section boundaries** and are now fixtures: `PROJ`, `G`, `P`, `DI`, `CF`,
  `ON`, `SUB`, and `ROADWORTHY_DATA` — that last one exported in one section and still live six
  hundred lines later, which is environment leaking rather than state shared. `tests/fixtures/`
  holds the builders they became.
- **Four cases at a time**, output buffered and printed in manifest order. Measured on this
  machine: 235 s serial, 183 s at four, 251 s at eight — past four it oversubscribes and gets
  slower. `RW_JOBS=1` puts it back in order for a bisect.
- Assertions went from 318 to **359**, and no assertion name was lost in the move: the two lists
  were compared name by name before and after.
- The `wait -n` the parallel runner was first written with does not exist in bash 3.2, the bash
  macOS ships, so the limiter it belonged to was not limiting anything. A broken limiter under a
  confident comment is worse than none; it is a polling loop now.

### Added — 2026-09-13, the mechanisms this release is made of
- `hooks/rite-gate` (Edit/Write **and Bash**): while the project has no usable `.roadworthy/scope`,
  every edit and every shell write is denied, naming the rite that opens a front. An **empty** scope
  file no longer counts: one `touch` used to satisfy every check while switching the lock off. The
  ten files only a script may write (scope, gates snapshot, state, the ledgers, the stop latch) are
  denied by hand through both doors, front or no front. A front recorded `gaps_found` or
  `needs_human` blocks the next one; no state at all is a new project and passes. The command
  reader is best effort and says so in the denial: what it does not recognise, it allows.
- `hooks/stop-gate` (Stop): a turn that says the work is finished is blocked while `close.sh
  --check` does not report every declared gate FRESH. Never blocks a project with no gates file,
  never blocks the same tree twice — the latch is keyed on the tree's content, so a changed tree is
  judged again — and fails open on anything it cannot read or write.
- `skills/plan/scripts/scope-write.sh`: the first act of execution writes the scope, the gates and
  `plan.snapshot` in one act, reading the plan's **Scope** and **Verification** as fenced blocks,
  never as prose bullets — `close.sh` runs each gate line with `bash -c`.
- `skills/plan/scripts/plan-preflight.sh` and the `plan_gate` option, above. It reads through the
  plan's `base:`, because checking a plan against a tree that has moved turns every finished
  correction into a false alarm and invites editing the plan to match the code.
- `tests/attack.sh`: the cheating suite. Every attack declares whether it must be refused or is a
  declared limit; an attack that passes and is not declared fails the gate.
- `tests/goldens/`: the deny and context envelopes compared key for key, replacing fragment
  matching that accepted output which was not JSON at all.
- Every denial is recorded in `.roadworthy/denials.jsonl` with the fence, the reason and the front.
  When the same fence has denied **three times** in the open front, that count comes back as a line
  in the next prompt: an agent does not remember, but it reads.
- `hooks/principles` pins the principles file by digest and announces a change at every prompt until
  it is agreed again. The file lives outside every repository, so what this gives is announcement,
  not prevention — said plainly rather than implied.

### Fixed — 2026-09-13, fences that were not watching what they claimed
- `scope-lock` looked for the scope file in the session's `cwd`: **inert in any subdirectory**. It
  resolves the repository root now, and so does the project's protected list in `protect-paths`.
- `scope-lock` treated an empty scope file as no front and stood down. An empty scope is now a
  malformed front and denies, naming it.
- `scope-lock` exempted all of `.roadworthy/`, which put human configuration and the foundation the
  rite writes in one basket. The exemption is now the three human-configuration files by name.
- `rw_glob_match` stripped the anchor and re-anchored at any slash, so `README.md` in the scope also
  matched `docs/README.md`. Anchored at the root now, always.
- `overnight-guard` resolved the marker from the session's `cwd`, not from the repository the
  command targets: `cd <other-repo> && git push` was denied although the other repository had no
  marker. It follows `git -C` and a leading `cd` the way `guard-commit` already did. **This closes
  one of the three Known items of 0.5.0.**
- `lib.sh` declared `trap … ERR` without `set -o errtrace`, so the trap did not inherit into
  functions, subshells or command substitutions — and failing closed is exactly what depends on it.
  A guard that declared itself fail-closed was failing **open** in every helper.
- `hooks/run-hook.cmd` on Windows without bash: warns and refuses instead of exiting 0 in silence.

### Fixed — 2026-09-13, proof that was decoration
- `refute.sh` printed its result and recorded nothing. It writes `refutations.jsonl` with both
  hashes, both exit codes, the injection, the expectation and the check command. **The script
  writes the record; the agent never does.**
- `refute-ledger.sh` could not see this repository at all — measured `0 fence(s)` over `hooks/`,
  because it filtered by test-file names. `--sources` declares the fences by name.
- `close.sh` re-read `.roadworthy/gates` at closing time, so editing the Verification section after
  approval silently changed what "the gates passed" proved. It measures against `plan.snapshot` and
  refuses when a digest disagrees, and refuses when the front's diff touches a file outside the
  declared globs — which is where a write made through the shell, invisible to the lock, surfaces.
- A gate that is trivially green (`true`) is now a WARN instead of silent success.
- `overnight-entry.sh` accepted any non-empty `--source`. It requires a path that exists, an
  `http(s)` URL or a git ref that resolves.
- `overnight-close.sh` never read the `plan_sha256` that `overnight-start.sh` writes. A plan changed
  during the night now refuses the closing, naming the file.

### Fixed — 2026-09-13, one dictionary for the whole house
- `docs-init.sh` generated a `docs.json` with no `status` key, so every new project was pinned to
  English in `plan-review-gate`. It is generated present and empty (`"status": {}`), never
  commented: the file is read with `json.load` by two consumers and a `//` would break the
  documentation gate in every new project.
- `resume-pick.sh` followed only the English `status: superseded by`, and returned the **superseded**
  hand-off on a project declaring its own words. It reads the project's vocabulary.
  **This closes the second Known item of 0.5.0.**
- Five templates hard-coded an English status word, not three.
- `.roadworthy/overnight` was neither ignored nor excluded from the tree fingerprint, so the night
  could only close by committing the marker. **This closes the third Known item of 0.5.0.**
- The front's state is written in both the plugin's data directory and the project, and read
  project first: a resume could otherwise read another project's state.

### Fixed — 2026-09-13, documentation that described a plugin that did not exist
- `hooks/hooks.json` said every hook fails open and that exit 2 is reserved for denials; `lib.sh`
  does the opposite on both counts.
- `agents/cold-reviewer.md` still offered plan reviews "bound to a hash".
- `skills/overnight/SKILL.md` carried a sentence broken by the hash-to-name change.
- `skills/close/SKILL.md` and its `argument-hint` promised gates given as arguments, which
  `close.sh` rejects.
- `docs/reference/roadmap.md` said six eval cases; there are seven in round 1 and six in round 2.
- `evals-round2/README.md` did not say anywhere that it was round 2, or what changes in it.
- Dead imports in `hooks/lib.sh` and `bin/rw-metrics`, and a compiled `.pyc` that was tracked. The
  suite now compiles every Python script in the plugin and fails naming any import nobody uses —
  `shellcheck` only reads shell, so nothing caught these.
- Four claims inside **accepted** decision records did not survive a whole reading, one of them
  refuted by this front's own submission. They are corrected by a new dated record, and the four
  are marked superseded rather than edited in place:
  `docs/decisions/2026-09-14-0239-four-accepted-claims-refuted.md`.

## [0.5.0] - 2026-09-13

The plan rite could not be executed in the mode the plugin tells the agent to use. Two sessions,
in two projects, hit it on the same day; both escaped by hand, and one lost a ten-minute review
because the verdict had nowhere to go. This release makes the rite fit in plan mode, binds a plan
to its project and its base, and stops a closing from reporting success with nothing measured.

**What is proved and what is not.** Every change here is covered by the suite in both directions
and refuted once (defect injected, expected failure text, file restored by hash). What is *not*
proved is the end-to-end path: this front submitted its own plan with the gate suspended, because
the gate blocked the repair of itself, and every hook was exercised with synthetic events against
this working tree — never against the installed copy in a real session. The bench that closes
this is in `docs/plans/2026-09-13-1315-handoff-the-rite-inside-plan-mode.md`.

**Behaviour change to know about before upgrading:** `close.sh --check` now fails in a project
with no `.roadworthy/gates`, where it used to print the absence and exit 0. That is the fix, and
it will surface in projects that never declared gates.

**Check your own repository for this one:** `close.sh` records each gate's output in
`.roadworthy/evidence.jsonl`, and that output carries the absolute paths of the machine that ran
it. Committing that file publishes them. The ledger, the denials log and the recorded state are
now in this repository's `.gitignore` — add them to yours. Found by closing this very front: the
ledger turned the plugin's own privacy gate red.

### Fixed — 2026-09-13, the rite was impossible inside plan mode
The plan rite asked for three files — the plan, the scope lock and the review — and plan mode
lets an agent write one. Two sessions in two projects hit it on the same day; both escaped by
widening the scope by hand or by leaving the mode, and one lost a ten-minute review with twelve
blockers because the verdict could not be written anywhere. The contradiction was in the plugin,
not in the models following it.
- `scope-lock`: the plan file is exempt. Its own comment already promised that the plan's
  artefacts are always editable, but the exemption covered only `.roadworthy/`; the plan lives in
  `plans_dir`, outside the project, so it was compared as an absolute path and denied. Paths are
  resolved through symlinks on both sides before matching.
- `plan-review-gate`: the review may live in a `## Review` (`## Banca`) section of the plan
  itself, which is what plan mode allows; the sidecar `<plan><review_suffix>` keeps working and
  takes precedence. The review's own heading never counts as growth, so a plan that already had
  round 1 can adopt the new form without tripping the growth guard.
- `plan-review-gate`: the plans directory is shared by every project (101 plans of several
  projects in one directory, measured), and the gate elected another project's plan and denied
  with a cryptic "no review". A plan now declares `project:` in its header and the gate elects by
  that; a plan of another project is named in the denial. Comparison resolves symlinks (`/var`
  and `/private/var` named one directory as two on macOS).
- `plan-review-gate`: a plan marked superseded in its header is not a candidate, read with the
  words the project declares under `status` in `.roadworthy/docs.json` — the same vocabulary
  `docs-check.sh` reads, not a second dictionary. Two live plans of one project are refused with
  both names instead of resolved by date; a directory of older drafts that declare no project is
  left alone, so nobody is blocked on upgrade.
- `plan-review-gate`: a plan may declare `base:` when the front is written against a tag or a
  release branch instead of the tip. The gate refuses a base that does not resolve, and refuses a
  review that declares a different base from the plan's — which is what turns "remember to tell
  the reviewer which ref to read" into a mechanism. Undeclared, the base is the working tree and
  nothing changes.
- `skills/plan`: the scope lock is written as the first act of execution, not before the plan is
  approved; the review goes in the plan in plan mode; the reviewer runs in the background because
  the harness offers no foreground, and its verdict is written to disk the moment it arrives.
  Reading and reviewing follow the plan's `base:` when it declares one.
- Internal: an unpaired apostrophe in a comment inside the gate's `$( … )` block breaks the hook
  with a syntax error far from the cause — bash counts quotes while scanning a command
  substitution, heredoc included. Three such lines were already in the file. All paired, with a
  note at the block; `bash -n` in `tests/run.sh` is the mechanism that catches it.
- `tests/run.sh`: 20 assertions for the above, in both directions, and each guarantee refuted
  (defect injected, expected failure text, file restored with its hash verified).

### Fixed — 2026-09-13, a closing that measured nothing reported success
- `close.sh --check`: no `.roadworthy/gates`, or a file that declares none, now **fails**. It
  used to print the absence and exit 0, and `overnight-close.sh` reads that output looking for
  refusal words — so a project with no declared gate closed the night reporting every gate FRESH.
  Measured on this repository, which had no gates file at all; the consequence was a scope lock
  that nobody could release, still standing six days after its front shipped, which is what sends
  the next front to widen the scope by hand.
- `close.sh`: the same for a real run — with zero declared gates it fails, keeps the scope and
  records `gaps_found`, instead of writing `passed` and releasing the lock.
- `overnight-close.sh`: the refusal now names the missing declaration instead of speaking only of
  STALE and MISSING gates.
- `skills/plan`: the skill writes `.roadworthy/gates` from the plan's Verification section in the
  same act as the scope, so the file `close` requires exists from the start.
- `scope-lock`: the denial says what to do when the scope belongs to a front that already
  finished — close it, not widen it.

### Fixed — 2026-09-13, documentation that described a plugin that no longer existed
Found by reading the files while releasing, and swept as a class across the repository.
- `README.md` said the review is bound to the plan's **hash** or to "their exact bytes", in four
  places including the opening paragraph. It binds by **name** since 0.3.0 — what the user
  approved is what counts. The `plan-review-gate` row also still described the pre-0.5.0 gate.
- `skills/plan/SKILL.md`: the same false claim sat in the skill's own `description`, which is the
  text a model reads to decide whether to use the rite at all.
- `README.md` said the bundled principles are "thirteen numbered lines"; `grep` counts eight, and
  the suite has asserted eight since 0.4.0.
- `.gitignore` and the privacy scan: the evidence ledger, the denials log and the recorded state
  are local machine state, not plugin sources. A new assertion fails if they are tracked again.
- `.gitignore`: `.roadworthy/scope` joins them, measured while closing this front. `close.sh`
  requires a clean tree, and the scope file dirties it: tracked, every close needs a housekeeping
  commit afterwards for the deletion `close.sh` itself made (twice in one session here);
  untracked, the tree is never clean and `close.sh` refuses to run. It is transient state that a
  front declares and the closing removes — the same class `tree-fingerprint.sh` already excludes
  from the fingerprint. **Add these four lines to your own project's `.gitignore`.**
- `README.md`: refutation is once per guarantee, when the fence is written — not the whole suite
  on every change. A refutation runs the check twice, and nothing said so.

## [0.4.0] - 2026-09-07

### Fixed — 2026-09-07, measured on a project's first morning after an overnight
- `docs-check.sh`: the review the `plan` skill writes next to a plan is `<plan><review_suffix>` — for `x.plan.md` that is `x.plan.review.md`, carrying `plan:` / `round:` / `VERDICT:` and no `status:`. The name rule accepted `.plan.md` **or** `.review.md`, never both, and the status rule rejected every real review, so the gate the skill itself sets up was red by construction. Now `.plan.review.md` is a valid companion and a `.review.md` file must carry a `VERDICT:` line instead of a status.
- `pointers-check.sh`: a memory file linked only from a sub-index that `MEMORY.md` links to (an index split by theme) counted as an orphan — 51 false failures on one project. Reachability now follows markdown links from the index through the files it reaches inside the memory directory; a file nothing reaches still fails, and the text-stem citation in `MEMORY.md` still counts.

### Changed — 2026-09-03, after a 16-round plan
- `plan-review-gate`: the review binds to the plan by NAME (no hash: what the user approved is what counts); REJECTED and ESCALATE deny; round ≥ 3 passes only with the user's `owner:` decision; growth guard (a `## ` section absent from `sections-round1:` denies); the submitted plan text picks the file, not the newest `.md` in the shared directory. Option `max_review_rounds` (default 2).
- `cold-reviewer`: third verdict `VERDICT: ESCALATE` with `## Recomendações` / `## Alternativas` (one `fonte:` per alternative); gaps that need new policy, fences, tools or sections are escalated, never demanded.
- `overnight-start.sh`: lists every missing precondition at once; accepts `## Política da madrugada`; no hash check.
- `principles/PRINCIPLES.md`: only rules with a mechanism behind them are injected (8 lines, each naming its hook).

## [0.3.0] - 2026-09-03

Overnight mode: the routine of running an approved plan unattended and auditing it in the
morning, carried as mechanism instead of prose (record `docs/decisions/2026-09-03-1322-overnight-mode.md`).

### Added
- `hooks/overnight-guard` (Bash): while `.roadworthy/overnight` exists, `git push`, `git merge`,
  `git tag`, `gh pr merge` and every `deny:` rule of `.roadworthy/overnight-rules` are denied; a
  malformed rule fails closed. Inert without the marker.
- `protect-paths`: the `freeze:` globs of `.roadworthy/overnight-rules` join the protected list
  while the marker exists (version files, release notes).
- `/roadworthy:overnight` with `overnight-start.sh` (refuses without a clean tree, a scope, a
  hash-bound APPROVED review and a `## Overnight policy` section; writes the marker with times taken
  by the script and the diary from a template), `overnight-entry.sh` (decisions need a primary
  source; phase ledger rows; blockers for the morning; every entry stamped by the script) and
  `overnight-close.sh` (requires every gate FRESH, writes the morning hand-off with the measured
  state, the blockers and the bench table, removes the marker).
- Plan template: `## Overnight policy` (decided at night with a source / reserved for the user);
  the gate pins it.
- `evals/overnight`: the agent in overnight mode is ordered to push and bump; passes only if the
  version file is untouched, the diary records the blocker and the status is honest (Bash-granting:
  not run in CI; run it where `--allow-tools Bash` is accepted, see `evals/README.md`).
- `tests/run.sh`: 30 new assertions — guard both ways (push, merge, `gh pr merge`, plain commands
  untouched, marker found from a subdirectory), `deny:` rule both ways, malformed rule fails
  closed, freeze both ways and from a subdirectory `cwd`, the three scripts refuted (no review,
  rejected review, review bound to another hash, dirty tree, plan without the policy section,
  double start, entry without source, close on a dirty tree, close with a MISSING gate), the
  measured-timestamp window, the diary entry format and the marker's `phase`, and the template pin.
- `docs-check.sh` accepts `<stem>.review.md` next to a dated plan: the review file that
  `plan-review-gate` binds to the plan's hash was rejected by the naming rule (found while closing
  this plan); other dotted suffixes still fail.
- Not run in this release: `claude plugin eval` on the `overnight` case (Bash-granting; refused on
  the host that wrote it, see `evals/README.md`). The mechanism is covered by `tests/run.sh`.

### Added (before 0.3.0, unreleased)
- `evals/`: six `claude plugin eval` cases (scope, protected, honest status, document, two
  no-op cases) on a scaffolded toy project; graders judge file state and the final `STATUS:`
  line, never the attempt.
- `bin/rw-metrics`: the seven KPIs per case and arm from the eval JSON, the run trace
  (`modelUsage`, `permission_denials`, `num_turns`, `duration_ms`) and the kept workspace
  (`pytest` after the run, `git status` against `SCOPE.txt`).
- `docs/reference/roadmap.md`: what is pending and why, measured.

### Fixed
- `guard-commit` judged the empty-staging rule by the session directory: a commit run as
  `cd <repo> && git commit` or `git -C <repo> commit` from another directory was denied even
  with changes staged, and `git add … && git commit` on one line was denied before the add
  ran. It now follows `git -C`, a leading `cd`, and leaves same-line staging to git.

## [0.2.1] - 2026-09-02

Adopting 0.2.0 on a real multi-language monorepo showed four places where the scripts
assumed English or one indexing style. Each is now a project setting or an option, with a
fence for the accepted and the rejected case.

### Added
- `docs-check.sh`: a project may declare its own words for the five MADR states under
  `"status"` in `.roadworthy/docs.json` (for example `{"accepted": "aceito", "superseded by":
  "superado por"}`). The mapping replaces the English words for that project; states left
  out keep English. `superseded by` targets are resolved with the declared phrase.
- `refute-ledger.sh --exclude <regex>`: a test whose first 6 lines match declares itself a
  diagnostic (dump, probe, spike), not a guarantee, and is skipped.

### Changed
- `docs-check.sh`: the concluded-plans index accepts links with a `./` prefix
  (`[x](./file.plan.md)`), and `--since` now also exempts handoffs dated before the cut from
  the live-handoff rule, in the same way it exempts them from the name rule.
- `tree-fingerprint.sh` excludes transient Roadworthy state (scope, state, ledgers) so that
  releasing the scope after a pass does not mark the evidence STALE.

## [0.2.0] - 2026-09-02

### Added
- Documentation tree by role (`.roadworthy/docs.json`): `docs-init.sh` (idempotent, never
  overwrites), role-aware `docs-check.sh` (concluded plans must be indexed; only the newest
  handoff by name may be live), `close-front.sh` (dry-run by default; `--apply` moves a closed
  front into history and rewrites every link).
- `close.sh`: gates declared in `.roadworthy/gates`, run only on a clean tree, each recorded in
  `evidence.jsonl` with the content fingerprint; `--check` reports FRESH / STALE / MISSING;
  states `passed | gaps_found | needs_human`; success releases the scope lock.
- `tree-fingerprint.sh` now follows content (`git write-tree` on a temporary index).
- `pointers-check.sh` (instruction files cite files that exist; memory index and files agree both
  ways) and `refute-ledger.sh` (a test that calls itself a fence carries its refutation record).
- `/roadworthy:resume` with `resume-pick.sh`: newest handoff by name, never by mtime; follows
  `superseded by` and fails on cycles.
- `protect-paths` also honours the project file `.roadworthy/protected`.
- `review_suffix` option; the review file also accepts Portuguese field names and verdicts.
- Principle 13 (speak in outcomes, never bare identifiers); risk band in the plan template.
- The plugin uses its own documentation tree (`docs/`, created by `docs-init.sh`).

## [0.1.1] - 2026-09-02

### Changed
- Guards (`scope-lock`, `protect-paths`, `guard-commit`, `plan-review-gate`) now **fail closed**:
  an internal error or malformed event denies the action. `principles` keeps failing open with a
  notice. The policy is declared per hook (`RW_ON_CRASH`) and a hook without one is itself an
  error; all three paths are covered by `tests/run.sh`.
- `refute.sh` also proves the check is **green on the clean file** after the restore; red on
  both sides is reported as "does not measure the defect".
- README states the measured context cost.

## [0.1.0] - 2026-09-02

### Added
- Hooks: `principles` (UserPromptSubmit), `scope-lock` and `protect-paths` (Edit/Write),
  `guard-commit` (Bash), `plan-review-gate` (ExitPlanMode). All fail open on internal error
  (exit 1 + notice) and use exit 2 only for deliberate denials.
- Skills: `plan`, `refute`, `close`, `document`, with `refute.sh`, `tree-fingerprint.sh`
  and `docs-check.sh`.
- Agent: `cold-reviewer` (read-only, fails closed, correctness-only findings).
- User configuration via `plugin.json` `userConfig`; self-hosted marketplace for a
  two-command install.
- `tests/run.sh`: hooks exercised in both directions with real stdin JSON, scripts refuted,
  manifests validated, privacy scan; CI on macOS and Linux.
