#!/usr/bin/env bash
# hygiene
# Run alone: bash tests/meta/hygiene.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── shell hygiene ────────────────────────────────────────────────────────────
# The fences are listed BY NAME, never by glob: `hooks/*` would sweep in hooks.json (which takes no
# comment header) and quietly cover a file nobody meant to check. The suite's own files ARE globbed,
# because there the glob is the point: a case that exists must be checked, and tests/cases.txt is
# what refuses a case file nobody declared.
section "shell syntax"
RW_FENCES="hooks/lib.sh hooks/principles hooks/protect-paths hooks/scope-lock hooks/guard-commit hooks/plan-review-gate hooks/overnight-guard hooks/rite-gate hooks/stop-gate"
# shellcheck disable=SC2086  # the two lists are deliberately word-split into arguments.
RW_SUITE="tests/run.sh tests/lib.sh tests/attack.sh $(echo tests/fixtures/*.sh tests/hooks/*.sh tests/scripts/*.sh tests/meta/*.sh)"
for f in $RW_FENCES skills/*/scripts/*.sh $RW_SUITE; do
  bash -n "$f" && ok "bash -n $f" || fail "bash -n $f"
done
if command -v shellcheck >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  shellcheck -S warning -x $RW_FENCES skills/*/scripts/*.sh $RW_SUITE \
    && ok "shellcheck (warning)" || fail "shellcheck"
else
  echo "  [SKIP] shellcheck not installed"
fi
python3 -c 'import json; json.load(open(".claude-plugin/plugin.json")); json.load(open(".claude-plugin/marketplace.json")); json.load(open("hooks/hooks.json"))' \
  && ok "manifests are valid JSON" || fail "manifest JSON"

rw_end
