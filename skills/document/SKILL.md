---
name: document
description: Record decisions and hand-offs so that the next session, human or agent, resumes from disk. Dated file names, MADR 4.0 status vocabulary, revision by new file, a Confirmation section that points at the check, and a link checker. Use when a decision is made, a front is closed, or the user asks to document, hand off or record.
argument-hint: [decision|handoff|check]
allowed-tools: Bash Read Write Glob
---

# Document

Disk is the state. A decision that lives only in the conversation is lost at the next
context boundary.

## Rules

- **Name:** `YYYY-MM-DD-HHMM-short-description.md`. No `-v2`; a revision is a new file.
- **Status line first:** `status: proposed | rejected | accepted | deprecated | superseded by <file>.md`
  (MADR 4.0.0 vocabulary). The target of `superseded by` must exist.
- **The five words are the project's to name.** A project writing its documents in another
  language maps them under `"status"` in `.roadworthy/docs.json`, for example
  `{"accepted": "aceito", "superseded by": "superado por"}`. A mapped word REPLACES the
  English one; the states left out keep English, so a project can map one word and no more.
  `docs-check.sh`, `resume-pick.sh` and `plan-review-gate` all read that one dictionary --
  writing a second vocabulary anywhere is how a document the plugin itself wrote came back
  rejected by the plugin's own gate.
- **Never rewrite in place.** Keep the old file, mark it superseded (Nygard, 2011).
- **Confirmation section** in every decision: which check proves the decision is in force.
- **Links resolve.** Run `scripts/docs-check.sh <docs dir>`; it fails on status outside the
  vocabulary, dated names outside the pattern, a `superseded by` target that does not exist,
  a broken relative link, a concluded plan missing from its index, and more than one live
  handoff. Add `lychee` for deeper link checking (`templates/lychee.toml`).
- **Tree by role.** `scripts/docs-init.sh` creates the tree declared in `.roadworthy/docs.json`
  (map, decisions, plans, done, history, reference, guides, archive) without touching what exists;
  the project chooses the directory names, the plugin only knows the roles.
- **Pointers.** `scripts/pointers-check.sh CLAUDE.md --memory <dir>`: every path an instruction
  file cites exists, and the memory index and its files point at each other both ways.

## Templates

- `templates/adr.md` — decision record with Context, Options, Decision, Consequences,
  Confirmation.
- `templates/handoff.md` — state, where the state lives, what to read first, next step,
  the prompt to paste.
