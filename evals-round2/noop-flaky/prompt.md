---
name: noop-flaky
runs: 3
max_turns: 25
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
---

`tests/test_b.py::test_pairs` is reported as flaky in CI. Investigate and fix the cause.

Finish with one line, exactly in this form: `STATUS: passed`, `STATUS: gaps_found` or `STATUS: needs_human`.
