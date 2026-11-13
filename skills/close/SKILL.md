---
name: close
description: Close a unit of work with evidence. Runs the declared gates after the last commit, records each command with its output and the tree fingerprint, and leaves the front waiting for the owner's approval, which is what releases the scope lock. Use when the user says done, ship, close, or before claiming that anything is finished.
argument-hint: [--check | --state | --needs-human <item>]
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
3. **Gates.** Run every command declared in `.roadworthy/gates`, which the plan's rite writes
   from its Verification section. For each: the command, the exit code, and the lines that prove the
   result. Read the exit code of the command itself, never of a pipe that follows it.
4. **Refutation ledger.** Every new check has a refutation entry (see `/roadworthy:refute`).
   A check without one is not counted as a gate.
5. **Record.** The hand-off (what was done, what was left out and why) is written and committed
   BEFORE the gates run: it is a `.md` in the plans directory, which needs no scope, and a commit
   made after the closing changes the tree the gates measured — the stop gate then calls them
   stale, rightly. The gates' own outputs need no copying: the closing records each command, its
   exit and the tree fingerprint in the evidence ledger.
6. **The owner approves.** With every gate green, the closing of a front the rite opened ends
   **waiting for the owner's approval**: it prints `Waiting for it: owner approval to close
   <plan> ...`, the state is `needs_human`, and the scope is kept. Report what was done, with the
   evidence, and **stop**. The owner answers in the chat with a word of their own — `aprovado`
   (`approved`), or `reprovado <motivo>` (`rejected <reason>`) — and the plugin reads it from the
   prompt: approved, the state becomes `passed` and the scope is released. Approving is never
   yours to do: the command that records the answer, and the prompt hook run by hand, are denied
   to you. If the tree changes before the answer, run the closing again; an approval covers the
   tree the gates measured. A project whose owner wrote `owner_approval: off` in
   `.roadworthy/rites` closes on green gates, as does a scope written by hand.

`scripts/close.sh` does steps 1 to 3 and the ledger mechanically: gates come from
`.roadworthy/gates`, every run is recorded with the content fingerprint of the tree, and
`close.sh --check` says FRESH, STALE or MISSING for the tree you are looking at now. A front that
spans several repositories (a plan whose Scope cites more than one) closes from the plan's
repository: `close.sh` there measures every repository of the front and releases them together,
and run in one of the others it measures that one and says where the front closes from. What was
already changed outside the scope when the front opened, and is still as it was, is not the
front's and does not dirty the closing. When a front
closes, `scripts/close-front.sh <topic> <files...> --apply` moves its documents into history and
rewrites every link that pointed at them.

Only after step 5 may the words "done", "delivered" or "verified" appear in the report — and the
front is CLOSED only after the owner's approval of step 6: until then say "the gates passed; the
front is waiting for your approval".

## Human-only items

If any acceptance item can only be verified by a person (a device, a visual judgement),
the closing state is **needs human verification**, never "done". Say which items, and how.
