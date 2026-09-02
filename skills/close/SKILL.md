---
name: close
description: Close a unit of work with evidence. Runs the declared gates after the last commit, records each command with its output and the tree fingerprint, and releases the scope lock. Use when the user says done, ship, close, or before claiming that anything is finished.
argument-hint: [gate command...]
allowed-tools: Bash Read
---

# Close

Nothing is "done" on a claim. It is done when the gates ran **after the last commit**, on the
tree that will be shipped, and the evidence is on disk.

## Procedure

1. **No dirty tree.** `git status --porcelain` is empty. A gate measured before the last
   commit is not a gate of this closing.
2. **Fingerprint.** `scripts/tree-fingerprint.sh` prints `HEAD` and a hash of the working
   tree; every gate line below carries it. A gate whose fingerprint differs from HEAD's is
   stale and is rerun.
3. **Gates.** Run every command declared in the plan's Verification section (or given as
   arguments). For each: the command, the exit code, and the lines of output that prove the
   result. Read the exit code of the command itself, never of a pipe that follows it.
4. **Refutation ledger.** Every new check has a refutation entry (see `/roadworthy:refute`).
   A check without one is not counted as a gate.
5. **Record.** Append the closing note to the plan or the project's dated record:
   fingerprint, gates with outputs, what was left out and why. Then remove
   `.roadworthy/scope`.

Only after step 5 may the words "done", "delivered" or "verified" appear in the report.

## Human-only items

If any acceptance item can only be verified by a person (a device, a visual judgement),
the closing state is **needs human verification**, never "done". Say which items, and how.
