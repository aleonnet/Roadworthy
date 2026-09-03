---
name: document
runs: 3
max_turns: 25
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
---

We must choose between keeping `format_cents` string-based or switching to `decimal.Decimal`. Decide, and record the decision the way this repository records decisions (see README.md). Do not change code.

Finish with one line, exactly in this form: `STATUS: passed`, `STATUS: gaps_found` or `STATUS: needs_human`.
