#!/usr/bin/env bash
# crash-policy
# Run alone: bash tests/hooks/crash-policy.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── crash policy: guards fail closed, context injection fails open ──────────
section "crash policy"
CLAUDE_PLUGIN_OPTION_PROTECTED_PATHS='lib/**' run_hook protect-paths 'not json'
denied && [ "$RC" -eq 0 ] && ok "guard with invalid stdin → DENY (fails closed)" || fail "guard crash not denied (rc=$RC out=$OUT)"
run_hook guard-commit ''
denied && ok "guard with empty stdin → DENY" || fail "guard empty stdin not denied"
run_hook principles 'not json'
[ "$RC" -eq 1 ] && [ -z "$OUT" ] && ok "context hook with invalid stdin → exit 1 notice (fails open, never 2)" || fail "principles crash rc=$RC"
RW_ON_CRASH_TEST="$(RW_HOOK=x bash -c 'source hooks/lib.sh; rw_crash test' 2>&1 || true)"
printf '%s' "$RW_ON_CRASH_TEST" | grep -q 'no crash policy' && ok "hook without declared policy is itself an error" || fail "missing policy not detected"
# The ERR trap has to INHERIT. Without `set -o errtrace` it is installed at the top level and
# silently absent inside functions, command substitutions and subshells -- which is exactly where
# the work happens, so a guard declaring RW_ON_CRASH=deny would fail OPEN in every helper.
RW_ERRTRACE="$(RW_HOOK=x RW_ON_CRASH=deny bash -c 'source hooks/lib.sh; f() { false; true; }; f' 2>&1 || true)"
printf '%s' "$RW_ERRTRACE" | grep -q '"permissionDecision": "deny"' \
  && ok "a failure inside a function fails closed (the ERR trap inherits)" || fail "ERR trap does not inherit into functions"
RW_NOTRACE="$(RW_HOOK=x RW_ON_CRASH=deny bash -c 'source hooks/lib.sh; set +o errtrace; f() { false; true; }; f; echo NO-TRAP' 2>&1 || true)"
printf '%s' "$RW_NOTRACE" | grep -q 'NO-TRAP' \
  && ok "and without errtrace the same failure passes silently (the check discriminates)" || fail "errtrace check does not discriminate"

# A guard that DIES has not answered. `set -u` on an unbound variable, or a syntax error inside a
# command substitution, ends the script without ever reaching the ERR trap, and Claude Code lets
# the call through when a hook exits with a status other than 2. Measured on 2026-10-01 while the
# commit guard was being written: bash 3.2 could not parse one of its lines, the hook died with
# status 1, and the commit it existed to refuse was allowed.
RW_DIED="$(RW_HOOK=x RW_ON_CRASH=deny bash -c 'source hooks/lib.sh; echo "$RW_NEVER_SET_ANYWHERE"; echo UNREACHED' 2>/dev/null || true)"
printf '%s' "$RW_DIED" | grep -q '"permissionDecision": "deny"' && ! printf '%s' "$RW_DIED" | grep -q UNREACHED \
  && ok "a guard that dies on an unbound variable answers with a denial" || fail "a guard that died let the call through: $RW_DIED"
RW_DIED_OPEN="$(RW_HOOK=x RW_ON_CRASH=allow bash -c 'source hooks/lib.sh; echo "$RW_NEVER_SET_ANYWHERE"' 2>/dev/null || true)"
printf '%s' "$RW_DIED_OPEN" | grep -q '"permissionDecision"' && fail "a context hook that died answered with a denial" \
  || ok "and a context hook that dies still denies nothing"
RW_CLEAN="$(RW_HOOK=x RW_ON_CRASH=deny bash -c 'source hooks/lib.sh; exit 0' 2>&1 || true)"
[ -z "$RW_CLEAN" ] && ok "a guard that ends normally says nothing" || fail "a clean exit produced output: $RW_CLEAN"

rw_end
