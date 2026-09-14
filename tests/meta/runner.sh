#!/usr/bin/env bash
# runner — the suite's own harness, measured instead of assumed.
# Run alone: bash tests/meta/runner.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

section "the case harness and the runner"

# A case that fails an assertion has to leave with a non-zero status: the runner reads the status,
# not the output.
cat > "$TMP/case-fail.sh" <<EOF
. "$ROOT/tests/lib.sh"
fail "planted"
rw_end
EOF
bash "$TMP/case-fail.sh" >/dev/null 2>&1 \
  && fail "a case with a failed assertion reported success" \
  || ok "a case with a failed assertion exits non-zero"

# A case that DIES before its last assertion is red too -- and this is the one that cannot be left
# to the shell. Measured 2026-09-14: with `set -u`, an unbound variable aborts the script and the
# EXIT trap sees $?=0 (bash 3.2), so the case exits 0 with half its assertions never run. That is
# what tests/run.sh shipped with in 0.6.0, and it is why rw_end sets a flag.
cat > "$TMP/case-die.sh" <<EOF
. "$ROOT/tests/lib.sh"
ok "ran this one"
echo "\$RW_NOT_A_VARIABLE"
ok "never reached"
rw_end
EOF
bash "$TMP/case-die.sh" >/dev/null 2>&1 \
  && fail "a case that died before the end reported success" \
  || ok "a case that dies before its last assertion is red"

# The discriminator: the same shape WITHOUT the flag. On bash 3.2 (macOS) it returns 0 -- the trap
# that shipped in 0.6.0 -- so the assertion above measures the mechanism and not the weather. On
# bash 4 and later the EXIT trap sees the abort's own status and the plain form is already red;
# the flag is what makes the case red on every shell. Written as a universal "returns 0" this
# assertion kept the CI red on ubuntu for three pushes (measured 2026-09-14 with
# `gh run view --log-failed`): the shell's behaviour is measured here, never assumed.
cat > "$TMP/plain-die.sh" <<'EOF'
set -euo pipefail
D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT
echo "$RW_NOT_A_VARIABLE"
EOF
plain_rc=0; bash "$TMP/plain-die.sh" >/dev/null 2>&1 || plain_rc=$?
plain_major="$(bash -c 'echo "${BASH_VERSINFO[0]}"')"
if [ "$plain_major" -le 3 ]; then
  [ "$plain_rc" -eq 0 ] \
    && ok "and on bash $plain_major the same abort without the flag returns 0 (the check discriminates)" \
    || fail "on bash $plain_major the plain form returned $plain_rc, not 0; the discriminator is not measuring what it claims"
else
  [ "$plain_rc" -ne 0 ] \
    && ok "on bash $plain_major the same abort without the flag already returns $plain_rc; the flag is what makes it red on bash 3 too" \
    || fail "on bash $plain_major the plain form returned 0; the shell changed under the discriminator"
fi

# THE MANIFEST IS THE FENCE. A runner that globs a directory loses a case the day the file is
# deleted, and says nothing.
bash tests/run.sh --check-manifest >/dev/null \
  && ok "the manifest and the case files agree" || fail "the manifest is already out of step"
grep -v 'plan-preflight' tests/cases.txt > "$TMP/cases-short.txt"
RW_MANIFEST="$TMP/cases-short.txt" bash tests/run.sh --check-manifest > "$TMP/short.out" 2>&1 \
  && fail "a case file nobody declared ran unnoticed" \
  || { grep -q 'plan-preflight' "$TMP/short.out" && ok "a case on disk and not in the manifest is named" || fail "the disagreement did not name the file: $(cat "$TMP/short.out")"; }
cat tests/cases.txt > "$TMP/cases-long.txt"; echo "tests/hooks/nao-existe.sh" >> "$TMP/cases-long.txt"
RW_MANIFEST="$TMP/cases-long.txt" bash tests/run.sh --check-manifest > "$TMP/long.out" 2>&1 \
  && fail "a declared case that does not exist passed" \
  || { grep -q 'nao-existe' "$TMP/long.out" && ok "a declared case that was deleted is named" || fail "the missing case was not named: $(cat "$TMP/long.out")"; }

rw_end
