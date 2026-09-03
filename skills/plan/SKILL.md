---
name: plan
description: Write a plan that is born ready, declare its file scope, and produce the adversarial review bound to the plan's hash that plan-review-gate requires. Use when starting any change that touches more than one file, before entering or leaving plan mode, or when the user asks for a plan.
argument-hint: [draft|scope|review|close]
allowed-tools: Bash Read Grep Glob
---

# Plan

A plan is born ready. Review confirms it; review never completes it. The goal is approval in
one round, at most one adjustment. Two rounds is the ceiling; if blockers do not fall between
rounds, escalate to the user with the delta, do not iterate.

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

## 4. Review bound to the hash

Run the `cold-reviewer` agent on the plan with the criteria from section 2. Write the verdict
to `<plan>.review.md` next to the plan:

```
plan: <plan file name>
plan-sha256: <sha256 of the plan file>
VERDICT: APPROVED | REJECTED
```

Then, and only then, submit the plan. `plan-review-gate` refuses submission without an
approved review for the exact bytes. Editing the plan invalidates the review; that is the
point.

## 5. Closing

`/roadworthy:close` removes the scope file after the gates pass.
