---
status: accepted
---

# Four accepted records said something the repository does not show

## Context and problem statement

The 0.6.0 front was raised by reading all 125 tracked files whole, line by line, on the owner's
order. Four claims inside **accepted** decision records did not survive that reading, and one of
them did not survive this front's own submission.

They are listed here rather than corrected in place because the house norm is Nygard's: *"we will
keep the old one around, but mark it as superseded"*. A record is what was believed on its date;
editing it in place erases the fact that it was believed.

The four, each with the line and what measured it:

**1. `ExitPlanMode` carries no plan text** — `docs/decisions/2026-09-13-1301-the-rite-inside-plan-mode.md:22`:
`` `.md` by modification time. The content-matching path that would have avoided this is dead in ``.
**Measured false on 2026-09-13**, by submitting the 0.6.0 plan itself: `plan-review-gate` elected
the right file out of 101 plans in a shared directory, which only happens when the text arrives and
the content path runs. The record was my source, and I had written the same claim into the plan
before the submission refuted it.

The consequence is not cosmetic. Believing the content path dead made the fragile part invisible:
the match is byte for byte, so one extra space, or an edit to the plan after the call was composed,
drops the election into `max(cands, key=os.path.getmtime)` — the date deciding in silence, in a
directory shared by every project. That is what acceptance 16 and 17 of the front measure.

**2. A review bound to its hash** — `docs/decisions/2026-09-03-1322-overnight-mode.md:38`:
`**1. Skill `/roadworthy:overnight`.** Preconditions checked by script: a plan with a review bound`.
The binding has been by **name** since 0.3.0: what the user approved is what counts, and editing the
plan afterwards does not void the approval. The sentence describes a plugin that stopped existing
three releases ago.

**3. A Confirmation that points at nothing** —
`docs/decisions/2026-09-02-2345-with-without-experiment.md:51`: the Confirmation cites `P.json`,
`C.json`, `P2.json`, `C2.json` and the `rw-metrics` CSVs "in the session scratchpad of 2026-09-02".
That scratchpad is gone. A Confirmation section exists so a reader can re-derive the numbers; one
that points into a deleted temporary directory is a Confirmation in form only. The reproducible part
of that record is the second line, `evals/README.md` and `evals-round2/`, and that is what it
should have carried alone.

**4. Dated names never collide** — `docs/decisions/2026-09-02-2009-docs-tree-by-role.md:18`:
`and two sessions never produce the same name. MADR allows the variation ("numbers … unique`.
The name has minute resolution. Two documents written in the same minute — one session writing a
record and a hand-off, or two sessions in one repository — produce the same name. The rule is
sound; the word *never* is not. It is a **declared limit**, not a defect to fix: adding seconds
would trade a rare collision for a name nobody can type from memory.

## Decision

One dated record supersedes the four, rather than four in-place edits.

The general rule this front learned, and the reason the record exists at all: **an accepted record
is a hypothesis about the code, not a measurement of it.** Its status says a decision was taken, and
says nothing about whether the code still matches. The three mechanisms that follow from that are
already built: `/roadworthy:plan` starts with an impact sweep over the real tree (principle 1);
`plan-preflight.sh` checks every citation by **content**, so a line that no longer says what a
document claims stops the submission; and the pre-flight reads through the plan's `base:`, because
checking against a tree that has moved invites editing the record to match the code, which is the
same failure pointing the other way.

## Consequences

- The four records stay on disk, marked `status: superado por <this file>`, which is this project's
  declared word for it (`.roadworthy/docs.json`).
- Claim 4 becomes a declared limit rather than a fix.
- Claim 1 becomes acceptance 16 and 17 of the 0.6.0 front: the election falls back to the
  transcript before it falls back to the date, and when it does fall back to the date it says so
  out loud.
- Claim 3 is the reason a Confirmation must cite something a reader can open later. Nothing
  enforces that yet; it is named in the roadmap rather than claimed here.

## Confirmation

- The four lines, read whole in the files on 2026-09-14: `sed -n '22p'`, `'38p'`, `'48,54p'` and
  `'16,20p'` of the four records named above.
- Claim 1 was refuted by the submission of the 0.6.0 plan on 2026-09-13, recorded in that plan's
  own inventory as defect 14.
- `bash skills/document/scripts/docs-check.sh docs` passes with the four marked superseded.
