#!/usr/bin/env bash
# plan-template
# Run alone: bash tests/scripts/plan-template.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

section "plan template"
grep -q '## Risk band' skills/plan/templates/plan.md && [ "$(grep -o -E '\*\*(protected|critical|standard|minimal)\*\*' skills/plan/templates/plan.md | sort -u | wc -l | tr -d ' ')" = "4" ] && ok "risk band with the four bands" || fail "risk band missing"
grep -q '^## Overnight policy' skills/plan/templates/plan.md && grep -q 'Reserved for the user' skills/plan/templates/plan.md && ok "overnight policy section with the two lists" || fail "overnight policy section missing"
# The `project:` line is copied by hand into plans that may live INSIDE the repository and be
# committed. Until 0.6.2 the template asked for an absolute path, so a committed plan carried
# `/Users/<name>/...` and the privacy scan of this very suite went red on it (measured 2026-09-14,
# docs/plans/done/2026-09-14-1841-readme-em-duas-linguas.md). The gate expands `~`
# (hooks/plan-review-gate, `same`), so `~` is what the template teaches, and no home path may
# appear anywhere in it.
grep -q -E '^project: ~/' skills/plan/templates/plan.md && ok "the project line is written from home with ~" || fail "project line does not start with ~/ (a committed plan with an absolute home path publishes the machine)"
grep -q -E '/Users/|/home/' skills/plan/templates/plan.md && fail "the template carries an absolute home path" || ok "no absolute home path anywhere in the template"

rw_end
