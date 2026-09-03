---
status: proposed
---

# Overnight mode: unattended execution of an approved plan, as a mechanism

## Context

Several teams run the agent unattended over a long window (a night, a weekend) on a plan
approved earlier, and audit the result in the morning on real hardware. The routine exists as
prose in memory files and in the headers of decision diaries. Prose does not survive a context
reset: in one measured case the agent described the routine from memory twice and got it wrong
twice, until it was told to read the sources. The routine is regular enough to be a mechanism.

What the sources agree on (five decision diaries, two run scripts, one delivery hand-off, four
memory files across three projects, 2026-08-05 to 2026-09-01):

1. It starts only by an explicit order of the user, on a plan that was already approved. It is
   never a clock.
2. Work proceeds phase by phase; one commit per phase; the suite green before each commit.
3. Every decision taken in flight goes to a dated diary with a **measured** timestamp (epoch ms
   and ISO, from `date` run in the act), the plan phase, the decision, the reason, and a primary
   source. Estimated timestamps were caught drifting into the future.
4. Anything with an established answer is decided at night, with the source recorded and marked
   for ratification in the morning. What waits for the morning is a class, not a list:
   irreversible, destructive, external, or reserved domains named by the project (pricing,
   permissions, radical design, hardware). A blocker is the exception, not the expectation.
5. Frozen for the night, whatever the project: publishing (`git push`, merges to the main line),
   version bumps and release notes, and writes to hardware or to other machines. Each project
   translates the class into concrete commands and files.
6. Delivery is a hand-off for the morning: measured state (branch, HEAD, clean tree, suite), a
   bench table `step | action | expected result`, the open blockers, and one prompt per outcome.

## Decision

Carry the routine as three opt-in pieces, all inert unless the user turns the mode on.

**1. Skill `/roadworthy:overnight`.** Preconditions checked by script: a plan with a review bound
to its hash (`plan-review-gate`), a declared scope, a clean tree. On entry it writes the marker
`.roadworthy/overnight` (start time measured, plan hash, current phase) and opens the diary from
a template with fixed sections: phase ledger (hash, gates, measured time), decisions (measured
timestamp, phase, decision, reason, primary source, "ratify in the morning"), blockers for the
morning, delivery (bench table and prompts per outcome). `overnight-entry.sh` appends an entry
with the timestamp taken by the script, so it cannot be estimated. `overnight-close.sh` requires
`close.sh --check` to report FRESH, writes the morning hand-off, and removes the marker.

**2. A guard that holds while the marker exists.** `guard-commit` (already on Bash) denies
`git push`, merges into the main line, and every command matching a line of
`.roadworthy/overnight-rules` (one regular expression per line: firmware upload, device install,
`sudo`, SSH to named hosts). `protect-paths` adds the freeze globs from the same file (version
files, release notes). Fails closed like the other guards; denials are structured decisions.

**3. Decision policy in the plan, not in memory.** The `/roadworthy:plan` template gains an
"Overnight policy" section with two lists: *decided at night with a source* (default: anything
with an established answer) and *reserved for the owner* (irreversible, destructive, risky, and
the domains the project names). `/roadworthy:overnight` refuses a plan without the section.

## Consequences

- Any agent, on any project, learns the routine from the skill and the plan, not from memory.
- The freezes become denials with a reason; the diary cannot carry an estimated time.
- The content of the decisions and the concrete command list stay with the project, where they
  belong (`.roadworthy/overnight-rules`).
- Cost: one skill, two scripts, two small extensions to existing hooks, one template section.

## Confirmation

- Refutation before it ships: an eval case where the agent in overnight mode is told to push and
  to bump; passes only if both are denied and the diary carries a measured entry. `tests/run.sh`
  injects the marker and calls `git push` against the guard.
- Not implemented by this record; it schedules the work in `docs/reference/roadmap.md`.
