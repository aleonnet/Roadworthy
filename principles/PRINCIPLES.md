# Roadworthy principles

Numbered lines below are injected at every prompt by the `principles` hook.
Each one names the failure it prevents AND the hook or script that enforces it: a rule with
no mechanism behind it is not injected (it lives in the docs), because an injected rule is
advice and only a gate holds under pressure (measured on 2026-09-03: 16 review rounds with
the ceiling written in text).
Replace this file with your own through the `principles_file` option; keep the
`N. ` numbering, everything else is free.

1. **Truth lives in the code you open now.** Docs, comments, handoffs and your own earlier notes are hypotheses; the proof is the file read in this turn. Mechanism: `/roadworthy:plan` starts with an impact sweep over the real tree.
2. **A number without the command that produced it is an opinion.** Every measurement in a deliverable travels with the command run in the act. Mechanism: `/roadworthy:close` records command, output and tree fingerprint together.
3. **A guarantee that never proved it can fail is not a guarantee.** Every fence is refuted once: inject the defect it claims to catch, watch it go red, restore byte for byte and verify the hash. Mechanism: `/roadworthy:refute`.
4. **A fix is not delivered until a cold reader has refuted the diff.** The reviewer sees only the diff and the criteria, reads only, and fails closed on anything uncertain. Mechanism: the `cold-reviewer` agent.
5. **The plan is born ready; two rounds is the ceiling; the third is the user's.** Review confirms a plan, never completes it; a gap that needs new policy, fences or sections is escalated, not built. Mechanism: `plan-review-gate` (rounds, ESCALATE, growth guard).
6. **One change, zero collateral damage.** Declare the files in scope before the first edit; anything outside stays untouched until the scope is widened on purpose. Mechanism: `scope-lock`, `protect-paths`.
7. **A commit is a real diff with a clean message.** No empty commits, no forbidden flags, no tool trailers; at night no push and no version bump. Mechanism: `guard-commit`, `overnight-guard`.
8. **Disk is the state, not the conversation.** Decisions go to a dated record, corrections to memory, measurements to the closing note, all before any context boundary. Mechanism: `/roadworthy:document`, `docs-check.sh`.
