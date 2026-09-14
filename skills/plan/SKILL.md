---
name: plan
description: Write a plan that is born ready, declare its file scope, and record the adversarial review that plan-review-gate requires — inside the plan itself when working in plan mode, where only one file may be written, or beside it otherwise. Use when starting any change that touches more than one file, before entering or leaving plan mode, or when the user asks for a plan.
argument-hint: [draft|scope|review|close]
allowed-tools: Bash Read Grep Glob
---

# Plan

A plan is born ready. Review confirms it; review never completes it. The goal is approval in
one round, at most one adjustment. Two rounds is the ceiling, enforced by the gate; the third is an escalation to the
user with the delta and sourced alternatives, never another fix.

## 1. Deep reading before a single line of plan

- The whole of every file you will change, not a window of lines.
- The primary documentation of every framework semantic you rely on, cited on the line.
- Every existing check that covers the area: tests, hooks, CI, contracts.
- Every consumer of what you change: whole-repository search, whole function per consumer.

**Read against the plan's base, not against the tree.** A front that branches from a tag or a
release branch is written against that ref, and the working tree may be far ahead of it — 75
commits, in the case that produced this rule. Declare the ref in the plan's `base:` line and do
every reading through it: `git show <base>:<path>` for a whole file, `git grep <pattern> <base>`
for the consumers. Without the declaration the base is the working tree, which is the common
case and stays the default. The base travels to the reviewer in section 4, so nobody has to
remember to warn it.

## 2. The plan file

Use `templates/plan.md`. Mandatory sections: **Context**, **Impact sweep** (commands and
their output), **Changes** (per file), **Scope** (globs), **Acceptance** (EARS form:
"WHEN `<condition>` THE SYSTEM SHALL `<behaviour>`", each with the command that proves it and
the output that means failure), **Verification** (gates run after the last commit), **Out of
scope**.

Wherever a premise is missing, write `[NEEDS CLARIFICATION: <question>]` instead of assuming.
A plan with open clarifications is not submitted; it is asked.

The template ends with an **Overnight policy** section: what is decided at night with a source
and what is reserved for the user. It is read only when the user orders unattended execution
(`/roadworthy:overnight`), and that skill refuses a plan without it — so write it for every plan
that may run without you.

Mass moves or renames get a **dry-run section**: every `mv` and every rewrite listed before
execution. Divergence between the dry-run and reality at execution time stops the work and
returns the delta to the user.

## 3. Scope lock — the first act of execution, not of planning

**One command does it, and nothing else may:** `scripts/scope-write.sh <plan.md>`. It reads the
plan's **Scope** and **Verification** fenced blocks and writes, in one act, `.roadworthy/scope`,
`.roadworthy/gates` and `.roadworthy/plan.snapshot` -- what was approved: the plan, the base
HEAD, the globs, the gates, and the digests of all three. From that moment `scope-lock` denies
edits outside the globs. Widen only with a written reason in the plan, by reopening the front.

**Why a snapshot.** `close.sh` used to re-read `.roadworthy/gates` at closing time, so editing
the Verification section after approval silently changed what "the gates passed" proves. The
closing now compares against the snapshot and refuses when a digest disagrees, and it refuses
when the front's diff (`base_head..HEAD` plus untracked) touches a file outside the declared
globs -- which is where a write made through the shell, invisible to the lock, finally surfaces.

**When to write it.** Plan mode lets you write exactly one file, the plan, so the scope file
cannot be written there — and it should not be: nothing is being edited yet. Write it as the
first act after the plan is approved, before the first edit of the front. The lock then guards
the work it was declared for, and `/roadworthy:close` releases it when the gates pass.

**Write the gates in the same act.** Copy the plan's **Verification** commands into
`.roadworthy/gates`, one per line. `/roadworthy:close` reads them and nothing else; a project
without that file cannot close, so the scope is never released and the next front finds a lock
nobody can open — which is how a scope lived six days past its front on this very repository
(measured 2026-09-13). A declared gate is also what stops a night from closing with the words
"every gate fresh" and nothing measured.

## 4. Review: one file in plan mode, two rounds, then the user

Run the `cold-reviewer` agent on the plan with the criteria from section 2, and give it the
plan's `base:` when the plan declares one, with the commands to read through it
(`git show <base>:<path>`, `git grep <pattern> <base>`) — otherwise it reads the working tree
and reports divergences that exist only against HEAD. The agent is launched by the session, not
by this skill's own tool set, and this harness runs subagents in the background only: there is
no foreground to ask for. So do nothing else while it runs, and **write the verdict down the
moment it arrives, before analysing it** — a review that lives only in the conversation is one
context boundary from being lost (measured 2026-09-13: ten minutes of review, twelve blockers,
gone if the session had been compacted).

Where to write it — two forms, same fields:

* **In plan mode**, where only the plan may be written: a `## Review` (or `## Banca`) section of
  the plan itself. The gate reads it there, and its own heading never counts as growth.
* **Outside plan mode**, or when you prefer to keep it apart: `<plan>.review.md` next to the
  plan (suffix configurable). The sidecar takes precedence when both exist.

```
plan: <plan file name>          (the sidecar only: the section is already in the plan)
base: <the plan's base ref>     (only when the plan declares one; must be the same ref)
round: <1 or 2>
sections-round1: <the plan's "## " headings at round 1, separated by " | ">   (write it at round 1)
VERDICT: APPROVED | REJECTED | ESCALATE
```

`sections-round1` comes from `grep '^## ' <plan>`. The review is bound to the plan by NAME:
what the user approves is what counts, and editing the plan afterwards does not void it.

**Which plan the gate calls the current one.** The plans directory is shared by every project,
so the header matters: `project:` binds the plan to its repository and a plan of another project
is named in the denial instead of being elected. A plan marked superseded in its header — in the
words the project declares under `status` in `.roadworthy/docs.json`, the same vocabulary
`docs-check.sh` reads — is not a candidate. Two live plans of the same project and nothing in the
call to tell them apart is refused with both names, not resolved by date: mark the older one
superseded, or move it out of the directory. A directory of older drafts that declare no project
is left alone, and the newest still wins there.

Rules the gate enforces (`plan-review-gate`): REJECTED denies; a `## ` section that was not in
`sections-round1` denies ("the plan is growing to satisfy the reviewer": stop and report);
round 3 does not exist — the reviewer writes an escalation (blockers that did not fall,
recommendations, sourced alternatives) and `VERDICT: ESCALATE`, which denies until the user
answers. Record the user's decision as an `owner:` line in the review with `VERDICT: APPROVED`
and then submit. A missing precondition of any kind is reported to the user, never satisfied
by adding policy, fences, tools or sections to the plan.

## 5. Closing

`/roadworthy:close` removes the scope file after the gates pass.
