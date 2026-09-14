#!/usr/bin/env bash
# validate
# Run alone: bash tests/meta/validate.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── official validation ──────────────────────────────────────────────────────
section "claude plugin validate"
if command -v claude >/dev/null 2>&1; then
  claude plugin validate . --strict >/dev/null 2>"$TMP/v" && ok "claude plugin validate --strict" || { fail "claude plugin validate"; cat "$TMP/v"; }
else
  echo "  [SKIP] claude CLI not installed"
fi

rw_end
