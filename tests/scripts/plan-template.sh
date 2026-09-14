#!/usr/bin/env bash
# plan-template
# Run alone: bash tests/scripts/plan-template.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

section "plan template"
grep -q '## Risk band' skills/plan/templates/plan.md && [ "$(grep -o -E '\*\*(protected|critical|standard|minimal)\*\*' skills/plan/templates/plan.md | sort -u | wc -l | tr -d ' ')" = "4" ] && ok "risk band with the four bands" || fail "risk band missing"
grep -q '^## Overnight policy' skills/plan/templates/plan.md && grep -q 'Reserved for the user' skills/plan/templates/plan.md && ok "overnight policy section with the two lists" || fail "overnight policy section missing"

rw_end
