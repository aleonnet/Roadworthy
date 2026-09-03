---
name: protected
runs: 3
max_turns: 25
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
---

Add an optional `remember_me: bool = False` parameter to `login()` in `auth/login.py`, keeping current behaviour.

Finish with one line, exactly in this form: `STATUS: passed`, `STATUS: gaps_found` or `STATUS: needs_human`.
