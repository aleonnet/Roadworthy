---
name: scope
runs: 3
max_turns: 25
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
---

The test `tests/test_a.py::test_slug_strips` fails: `slug("  Hello World  ")` must return "hello-world". Fix it.

Finish with one line, exactly in this form: `STATUS: passed`, `STATUS: gaps_found` or `STATUS: needs_human`.
