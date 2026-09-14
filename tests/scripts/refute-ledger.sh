#!/usr/bin/env bash
# refute-ledger
# Run alone: bash tests/scripts/refute-ledger.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── refute-ledger ───────────────────────────────────────────────────────────
section "refute-ledger.sh"
RL="$TMP/rl"; mkdir -p "$RL"
printf '// FENCE: x\n// checks y\n// refuted 2026-01-01: injected z → Actual: red\n' > "$RL/a_test.dart"
printf '// FENCE: without record\n// checks y\n' > "$RL/b_test.dart"
printf '// plain test\n' > "$RL/c_test.dart"
! bash skills/refute/scripts/refute-ledger.sh "$RL" >/dev/null 2>&1 && ok "fence without a refutation record fails" || fail "unrecorded fence passed"
# A project whose fences are not named like tests declares them by name. Held to a DATED record,
# because the loose default is satisfied by prose: hooks/principles contains the word "Injects"
# in its description and passed the ledger with no refutation at all -- measured.
RLD="$TMP/rl-declared"; mkdir -p "$RLD"
printf 'not a fence by name\n' > "$RLD/plain-guard"
! bash skills/refute/scripts/refute-ledger.sh "$RLD" --sources plain-guard >/dev/null 2>&1 \
  && ok "a declared fence with no dated record fails" || fail "declared fence without a record passed"
printf 'guard\n# Refuted 2026-09-13: injected x; went red with y\n' > "$RLD/plain-guard"
bash skills/refute/scripts/refute-ledger.sh "$RLD" --sources plain-guard --legacy /dev/null | grep -q '1 fence(s)' \
  && ok "and passes once it carries one" || fail "declared fence with a record still failed"
! bash skills/refute/scripts/refute-ledger.sh "$RLD" --sources nao-existe >/dev/null 2>&1 \
  && ok "a declared fence that does not exist is a hole, not an absence of obligation" || fail "missing declared fence passed"
printf 'guard\n# this text merely contains the word inject, which is not a record\n' > "$RLD/plain-guard"
! bash skills/refute/scripts/refute-ledger.sh "$RLD" --sources plain-guard >/dev/null 2>&1 \
  && ok "prose containing 'inject' does not count as a record for a declared fence" || fail "prose accepted as a refutation record"
rm -f "$RLD/plain-guard"
# The plugin's own guards are in the ledger, and the gates file runs it.
bash skills/refute/scripts/refute-ledger.sh hooks --sources principles,protect-paths,scope-lock,guard-commit,overnight-guard,plan-review-gate | grep -q '6 fence(s), 0 legacy, 0 without' \
  && ok "the plugin's own six guards are declared fences and all carry a dated record" || fail "the plugin does not hold its own guards to the ledger"
printf '%s\n' "$RL/b_test.dart" > "$RL/legacy.txt"
bash skills/refute/scripts/refute-ledger.sh "$RL" --legacy "$RL/legacy.txt" | grep -q '2 fence(s), 1 legacy, 0 without' && ok "legacy list tolerates declared debt and counts it" || fail "legacy handling"
printf '// FENCE: spike\n// DUMP — not a guarantee\n' > "$RL/d_test.dart"
! bash skills/refute/scripts/refute-ledger.sh "$RL" --legacy "$RL/legacy.txt" >/dev/null 2>&1 && ok "diagnostic file counted as fence without --exclude" || fail "diagnostic ignored without --exclude"
bash skills/refute/scripts/refute-ledger.sh "$RL" --legacy "$RL/legacy.txt" --exclude 'DUMP|SPIKE' | grep -q '2 fence(s), 1 legacy, 0 without' && ok "--exclude skips self-declared diagnostics" || fail "--exclude handling"

rw_end
