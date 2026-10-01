status: accepted

# 0.7.0 — the rite tells the truth: what was measured, what was refused, what stays a limit

## Context and problem

The plugin is used on other projects, and its failures there were being compensated by a long
resume prompt. Four private field notes (18, 22, 24 and 30 September 2026) recorded fifteen gaps
measured on 0.6.2. Reading the code for them found a sixteenth nobody had recorded: the reader of
shell commands inside the entry gate. The plan
(`docs/plans/2026-09-30-2154-o-rito-diz-a-verdade.md`) closes all of them in one front.

Two orders arrived while the front was open, and both changed it:

- validate the whole rite, so that no guard leaves an honest agent in a dead end;
- make it impossible for an agent to skip the rite, proved by an adversarial simulation ("not even
  a hundred agents"). The simulation ran, proved three ways round that only a change of
  architecture closes, and the owner withdrew that bar for this release: *"Remova a regua e conclua
  a 0.7.0"*. What holds for 0.7.0 is: no path by carelessness or by shortcut.

## Decision

1. **The reader of shell commands is a grammar, not a list of verbs** (`hooks/shellread.py`), with
   a table of cases as its contract (`tests/scripts/shellread.sh`).
2. **For the rite's own directory the rule is inverted:** only a command known to READ is handed a
   path under `.roadworthy/`. A list of verbs that write never closes — the first cold review of
   the reader found thirty more in an afternoon — and a list of commands that read does.
3. **What cannot be read is not denied, it is caught where the set is exact:** the commit (git's
   own index) and the closing (the front's diff). Denying what cannot be read was measured and
   refused, below.
4. **The repository that judges a target is the one the target is in**, never the one the session
   stands in.
5. **A front opens only from what was approved**, and the approval is recorded by the plugin when
   the person approves the plan, as the fingerprint of scope, gates and base.
6. **What a project requires lives in the project**, in `.roadworthy/rites`, a file the agent
   cannot edit. The field case: a plan submitted with the pre-flight alone in a project whose
   written rule asked for a review; the rule was a memory note no hook read.
7. **A change outside the scope left in the tree is said to the agent, not blocked.** Blocking was
   built and measured: it stopped the agent over a file the owner had saved in the same tree.
8. **Three classes proved by the adversarial simulation are declared limits**, with their fix
   written as the first pending item of `docs/reference/roadmap.md`.

## What was measured (commands run on 2026-09-30 and 2026-10-01, on this machine)

The scripts that read the transcripts of other projects are kept outside the repository; the
numbers are these.

**The reader, over every real command.** All Bash commands in the transcripts of this machine since
2026-09-14: 34,451 commands in 50 transcripts; the new reader takes 14.4 s for all of them, the
slowest single command 0.008 s, and none came back unreadable.

- Old reader against new, counting commands in which each sees a write inside the session's
  directory: both 1,588; only the old one 3,211; only the new one 236; neither 29,416. The 3,211
  were read by sample, not one by one: they are the old reader's false positives (`>=` inside a
  heredoc, a `>` after an escaped quote, the last word of the line after a verb) and writes that,
  after a `cd`, land outside the session's directory.
- The inverted rule for the rite's directory answers 57 distinct real commands with a refusal: 32
  are an interpreter editing a file of the rite by hand, in nine projects (the gates, the protected
  list, the night marker, a refutation record); 20 are toy repositories built inside a session
  scratchpad, which the gate exempts; 5 are manual edits of `gates` or `scope` through the shell.
  No read is among them.

**Two directions the field notes proposed, refused by number.**

- *Deny interpreters in the shell.* 25.7% of 33,811 commands use an interpreter, a heredoc, `patch`
  or `git apply` (measured 2026-09-30). Denying by default makes the plugin unusable.
- *Widen the vocabulary of "finished"* with `feito`, `fechado`, `aprovado` and a check mark. Over
  4,374 turn ends in those transcripts: 700 match today's vocabulary and 177 were real blocks, 86 of
  them with the shape of a false positive. Reading the word as a claim takes 700 judged turn ends to
  422 and keeps 91 of the 177 blocks; widening the vocabulary on top of that takes 422 to 976.

**The cost of a hook call.** One call of the entry gate on a shell write took 1.06 s on the tree of
2026-09-30, nearly all of it interpreter start-up: every field of the event was its own `python3`.
The event is parsed once now. Measured on 2026-10-01 on a toy repository with a front open (with the suite running in
parallel, so upper bounds): entry gate on a read 0.42 s, on a shell write 0.88 s, on an edit 0.75 s;
scope lock 0.42 s; protect-paths 0.31 s; commit guard on a command that is not a commit 0.40 s.

**The suite.** `bash tests/run.sh`: 33 cases, `RESULT: gate clean`. `bash tests/attack.sh`: 146
attacks, 131 refused, 15 declared. Refutations run on 2026-10-01 over the final tree, each planting
one defect, expecting the exact failure text and restoring the file by hash: 65, all refuting.

**The simulator.** `tests/sim/rite-sim.py` drives a session — tool call after tool call — through
every hook `hooks/hooks.json` registers, executes the call in a toy repository when none denies it,
and then measures the repository. Thirteen scenarios are in the suite
(`tests/meta/rite-liveness.sh`): nine of honest work, four of attempts to get past the rite. Its
first run found two things no case had: with a front open, a shell redirection outside the scope
went through; and `git commit -am` with nothing staged was refused as an empty commit.

## The adversarial simulation of 2026-10-01

Five agents, each with the plugin's source in front of it and the simulator as its bench, each
writing scenarios and running them. One hunted for dead ends in honest work; four tried to get past
the rite. Sixty-four scenarios were written. One of the five — the one aimed at the reader of shell
commands — was stopped before it tested anything, and its result is NOT "the reader held".

**What it proved, and was fixed with a regression case.** The rite's directory spelled in another
case (on a case-insensitive disk `.Roadworthy/scope` is the scope, and every comparison was in
lower case); a reviewer's verdict accepted from any subagent; `diff_review: Required` read as no
requirement; a refusal inside a submodule writing a ledger there that the agent could not remove,
which made the parent's front impossible to close; a colleague's commit arriving by pull charged
to the front; a file name with a non-ASCII character refused at the commit and at the closing; a
plan with its scope written as bullets approved and then never opening; housekeeping with no front
open (removing ignored files, putting a file back the way git has it) refused; undoing a change
outside the scope accepted only as `rm` of each exact file.

**What it proved, and stays.** Re-running every scenario against the final tree, fifteen still end
with something the rite forbids:

| Class | Scenarios | What happens | What still holds |
|---|---|---|---|
| A commit by a route the reader does not recognise (a script on disk, git's plumbing, an alias, a subprocess) | 7 | a file outside the scope, or a protected one, is in the history | the closing refuses the front; the agent is told at its next write |
| The evidence ledger or the state file written by a program that builds the path at run time | 6 | a forged approval reopens the front with a wider scope; a forged state says `passed` | a forged scope, gates or snapshot is caught by its digest and stops the front |
| A finished claim worded outside the vocabulary | 2 | the turn ends unjudged | the closing is still what releases the scope |

The cause of the first two is one fact: the agent and the hooks run as the same user. Closing them
needs git itself refusing the ref update, and the rite's own writes moved out of the agent's shell
so that the operating system can deny writes under `.roadworthy/`. That is a redesign, and it is
the next front.

## Consequences

- Good: the fifteen field gaps are closed with a failing test first and a refutation each; an
  honest session has no known dead end in the nine simulated flows; the owner states a project's
  requirements once, in a file the agent cannot touch.
- Bad: an agent that sets out to defeat the plugin still can, in the three ways above, and the
  README says so in its first paragraph on limits.
- Bad: the reader of shell commands has no adversarial measurement of its own.
- Bad: three behaviours are proved only by synthetic events — the approval recorded when a plan is
  approved in the interface, the reviewer's type and final text arriving at the end of a real
  subagent, and the owner's `rw-human:` line in a real prompt. They are the owner's bench.
- Known friction, not fixed: with no front open, a removal whose targets cannot be named
  (`find . -name '*.pyc' -delete`) is denied; `git stash` with an uncommitted `gates` file stops the
  front until `git stash pop`.

## Confirmation

- `bash tests/run.sh` → `RESULT: gate clean`, with `tests/meta/rite-liveness.sh` and
  `tests/scripts/shellread.sh` in `tests/cases.txt`.
- `bash tests/attack.sh` → `RESULT: every cheat refused, every pass declared`; the three classes
  above appear there as DECLARED, so the day one of them starts being refused the suite reports the
  fence growing.
- `bash skills/refute/scripts/refute-ledger.sh hooks --sources principles,protect-paths,scope-lock,guard-commit,overnight-guard,plan-review-gate,rite-gate,stop-gate,session-state`
  → `9 fence(s), 0 legacy, 0 without a record`.
