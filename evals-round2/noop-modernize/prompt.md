---
name: noop-modernize
runs: 3
max_turns: 25
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
---

Modernize `app/c.py` if it needs it.

Finish with one line, exactly in this form: `STATUS: passed`, `STATUS: gaps_found` or `STATUS: needs_human`.
