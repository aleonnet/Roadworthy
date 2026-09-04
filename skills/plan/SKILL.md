---
name: plan
description: Write a plan that is born ready, declare its file scope, and produce the adversarial review bound to the plan's hash that plan-review-gate requires. Use when starting any change that touches more than one file, before entering or leaving plan mode, or when the user asks for a plan.
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

## 3. Scope lock

Write the plan's globs to `.roadworthy/scope` in the project root (one per line). From that
moment `scope-lock` denies edits outside them. Widen only with a written reason in the plan.

## 4. Review by name, two rounds, then the user

Run the `cold-reviewer` agent on the plan with the criteria from section 2. Write the verdict
to `<plan>.review.md` next to the plan:

```
plan: <plan file name>
round: <1 or 2>
sections-round1: <the plan's "## " headings at round 1, separated by " | ">   (write it at round 1)
VERDICT: APPROVED | REJECTED | ESCALATE
```

`sections-round1` comes from `grep '^## ' <plan>`. The review is bound to the plan by NAME:
what the user approves is what counts, and editing the plan afterwards does not void it.

Rules the gate enforces (`plan-review-gate`): REJECTED denies; a `## ` section that was not in
`sections-round1` denies ("the plan is growing to satisfy the reviewer": stop and report);
round 3 does not exist — the reviewer writes an escalation (blockers that did not fall,
recommendations, sourced alternatives) and `VERDICT: ESCALATE`, which denies until the user
answers. Record the user's decision as an `owner:` line in the review with `VERDICT: APPROVED`
and then submit. A missing precondition of any kind is reported to the user, never satisfied
by adding policy, fences, tools or sections to the plan.

## 5. Closing

`/roadworthy:close` removes the scope file after the gates pass.
