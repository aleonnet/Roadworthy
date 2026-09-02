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
- **Never rewrite in place.** Keep the old file, mark it superseded (Nygard, 2011).
- **Confirmation section** in every decision: which check proves the decision is in force.
- **Links resolve.** Run `scripts/docs-check.sh <docs dir>`; it fails on status outside the
  vocabulary, dated names outside the pattern, a `superseded by` target that does not exist,
  and a broken relative link. Add `lychee` for deeper link checking (`templates/lychee.toml`).

## Templates

- `templates/adr.md` — decision record with Context, Options, Decision, Consequences,
  Confirmation.
- `templates/handoff.md` — state, where the state lives, what to read first, next step,
  the prompt to paste.
