---
name: overnight
description: Unattended execution of an approved plan, started only by the user's explicit order. Opens a decision diary whose timestamps are taken by script, freezes publishing, version bumps and hardware writes until the morning, and closes with a hand-off the user audits on waking. Use ONLY when the user orders overnight (or unattended) execution; never start it on your own.
argument-hint: start <plan.md> <topic> | entry ... | close
allowed-tools: Bash Read Grep Glob Edit Write
---

# Overnight

The user approves a plan, orders it executed unattended, and audits the result in the morning
on the real thing. Everything that makes that audit possible is mechanical here.

## When

Only after the user says so, in words, for this plan. An approved plan is the precondition,
not the trigger. There is no clock: nothing starts because it is late.

## Start

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/overnight/scripts/overnight-start.sh" docs/plans/<plan>.md <topic>
```

Refuses unless: no marker is on yet; `.roadworthy/scope` exists; the plan's review file
(`<plan><review_suffix>`, default `.review.md`) says `VERDICT: APPROVED` for the plan's current
SHA-256; the plan has a `## Overnight policy` section; and the tree is clean. On success it writes
the marker `.roadworthy/overnight` (start time taken by the script, plan, hash, topic, diary path,
current phase) and creates the diary `<YYYY-MM-DD-HHMM>-overnight-<topic>.md` in the decisions
directory declared in `.roadworthy/docs.json`. The marker is local state: list
`.roadworthy/overnight` in the project's `.gitignore`, next to `.roadworthy/scope`.

While the marker exists, `overnight-guard` denies `git push`, `git merge`, `git tag`, `gh pr merge`
and every `deny:` rule of `.roadworthy/overnight-rules`; `protect-paths` denies edits to every
`freeze:` glob of the same file. Write that file per project, before the first night:

```
# .roadworthy/overnight-rules — frozen for the night
deny: pio run .* -t upload
deny: flutter (install|run)
deny: (^|[;&| ])sudo( |$)
freeze: pubspec.yaml
freeze: CHANGELOG.md
```

## During the night

Phase by phase, one commit per phase, the suite green before each commit. Every decision taken in
flight goes to the diary through the script, never by hand, so the timestamp is measured:

```bash
overnight-entry.sh --phase F2 --decision "..." --reason "..." --source "<primary source>"
overnight-entry.sh --phase-done F2 --sha "$(git rev-parse --short HEAD)" --gates "suite 291 green · analyze 0"
overnight-entry.sh --blocker "..."          # something only the user can decide; skip it, continue
```

What may be decided at night and what waits is written in the plan's **Overnight policy**, not
remembered. Default: anything with an established answer (a primary document, a benchmark, the
project's own canon) is decided, recorded with the source and marked "ratify in the morning";
anything irreversible, destructive, external, or in the domains the plan reserves is a blocker.

## Close

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/overnight/scripts/overnight-close.sh" [--run]
```

Refuses unless the tree is clean and `close.sh --check` reports every gate FRESH (`--run` runs
`close.sh` first). Writes `<YYYY-MM-DD-HHMM>-handoff-overnight-<topic>.md` in the plans directory:
measured state (branch, HEAD, tree, unpushed commits), the diary, the blockers copied from it, and
the bench table the user fills in the morning (`step | action | expected result`), with one prompt
per outcome. Then removes the marker; push, bump and release notes become possible again, for the
user to order.

## What this skill never does

- Start on its own, or because a plan exists.
- Push, merge, tag, bump, or touch hardware — the guard denies it, and so do you.
- Decide something the plan reserves for the user, or write a timestamp by hand.
