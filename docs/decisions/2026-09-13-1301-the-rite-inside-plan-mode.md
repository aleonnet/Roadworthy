---
status: accepted
---

# The plan rite must fit inside plan mode

## Context and problem statement

The `plan` skill asks for three files: the plan, `.roadworthy/scope`, and the review next to the
plan. Claude Code's plan mode lets an agent write exactly one file, the plan. So two of the four
steps of the plugin's own rite are impossible in the mode the skill tells the agent to use
("before entering or leaving plan mode").

Measured on 2026-09-13, in two projects on the same day:

- `scope-lock` denied the write of the plan file, because the plan lives in `plans_dir`, outside
  the project, and was compared as an absolute path against the project's globs. The way out
  taken in the field was appending the path to `.roadworthy/scope` by hand — the widening the
  roadmap already records as a field defect.
- `plan-review-gate` denied `ExitPlanMode` naming a plan of a *different project*: the plans
  directory is shared, 101 plans of several projects sat in it, and the gate elects the newest
  `.md` by modification time. The content-matching path that would have avoided this is dead in
  this harness: `ExitPlanMode` carries no plan text, as its own tool description states, and the
  suite proved that path only by injecting the field by hand.
- A cold review of ten minutes that rejected a plan with twelve blockers could not be written
  anywhere: the mode forbids the second file. The verdict survived only in the conversation, one
  context boundary away from being lost — in a plugin whose first principle is that disk is the
  state.

A rite that cannot be executed is not followed; it is worked around. Every model that met it
started improvising, and the improvisations are the failures above.

## Considered options

1. **Tell the agent to leave plan mode to complete the rite.** What the field did twice. It puts
   the agent outside the mode with no scope declared — the window in which the guards are off is
   exactly when the first edits happen. Rejected.
2. **Drop the review requirement in plan mode.** Removes the contradiction by removing the
   guarantee. Rejected.
3. **Let the review live inside the plan.** The one file plan mode allows carries both. The gate
   reads the same fields from a `## Review` section; the sidecar file keeps working and takes
   precedence. Chosen.

## Decision

Option 3, with three consequences made mechanical rather than advisory:

- **The plan file is exempt from the scope lock** (`plans_dir`, resolved through symlinks). The
  guard's own comment already promised this; only the code did not.
- **The plan declares `project:`**, and the gate elects by the project, not by date. A plan of
  another project is named in the denial. A plan marked superseded — in the words the project
  declares under `status` in `.roadworthy/docs.json`, one vocabulary for the whole house — is not
  a candidate, and two live plans of one project are refused with both names rather than resolved
  by date. Older drafts that declare no project keep the previous behaviour, so no existing user
  is blocked on upgrade.
- **The plan may declare `base:`** when the front is written against a tag or a release branch
  instead of the tip. The gate refuses a base that does not resolve and refuses a review made
  against a different base. Without this the reviewer reads the working tree and reports
  divergences that exist only against HEAD; in the field that was handled by warning the reviewer
  three times in its prompt, which is advice, and advice is what this plugin exists to replace.

## Consequences

- Good: the whole rite runs inside plan mode, with one file, and the plan reaches the approval
  screen without a single gesture outside the mode. The review is on disk the moment it exists.
- Good: the user reads the review together with the plan on the approval screen.
- Bad: a plan that declares neither `project:` nor `base:` keeps the old ambiguity. That is
  deliberate — the alternative blocks every directory of legacy drafts on upgrade.
- Accepted limit, recorded in `docs/reference/roadmap.md` under Declared limits: the scope lock
  watches the edit tools, not the shell. Deciding whether an arbitrary shell command writes
  outside the scope has no exact answer, a guard that fails open on what it cannot parse is
  decoration, and one that fails closed denies nearly every command.

## Confirmation

The decision is in force while `bash tests/run.sh` prints `RESULT: gate clean` with the twenty
assertions of the sections "scope-lock" and "plan-review-gate (plan mode writes one file)", each
exercised in both directions. Every guarantee was refuted before this record was written: the
defect injected, the expected failure text observed, the file restored with its hash verified
(`skills/refute/scripts/refute.sh`).
