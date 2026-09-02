---
name: resume
description: Resume work from disk, not from memory of the conversation. Reads the documentation map, picks the newest handoff by name, states what was read and the confirmed state before doing anything. Use at the start of a session, after /clear or /compact, or when the user says resume, continue, pick up, where were we.
allowed-tools: Bash Read Glob
---

# Resume

The conversation is not the state; the disk is. Before acting:

1. **Map first.** Read the documentation map declared in `.roadworthy/docs.json` (default
   `docs/README.md`). It says what to read for which task.
2. **Newest handoff by name.** `scripts/resume-pick.sh` prints the handoff to read first. It sorts
   by name, never by modification time, and follows `superseded by` pointers. Read the whole file.
3. **Confirm the state.** Measure what the handoff claims: branches, HEADs, dirty trees, gate
   states (`close.sh --state`, `close.sh --check`). Where disk and handoff disagree, disk wins,
   and you say so out loud.
4. **Declare what you read.** The first message of the session lists the files read and the
   confirmed state, so the person sees continuity restored instead of guessing.

Only then take the next concrete step the handoff names.
