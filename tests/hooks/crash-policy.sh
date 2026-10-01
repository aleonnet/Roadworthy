#!/usr/bin/env bash
# crash-policy
# Run alone: bash tests/hooks/crash-policy.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── crash policy: guards fail closed, context injection fails open ──────────
section "crash policy"
CLAUDE_PLUGIN_OPTION_PROTECTED_PATHS='lib/**' run_hook protect-paths 'not json'
denied && [ "$RC" -eq 0 ] && ok "guard with invalid stdin → DENY (fails closed)" || fail "guard crash not denied (rc=$RC out=$OUT)"
# What that denial SAYS (0.7.1). The parse failed inside a command substitution, where the ERR trap
# is inherited: the trap fired there first, printed a denial that the substitution CAPTURED as if it
# were the parsed fields, and the captured text was then handed to `eval` -- so the guard denied by
# accident, with `internal error at line 95` for a reason and `command not found` on stderr
# (measured 2026-10-01). The reason names the invalid input now, and nothing captured is executed.
printf '%s' "$OUT" | grep -q 'invalid JSON on stdin' && ! printf '%s' "$OUT" | grep -q 'internal error' && ! printf '%s' "$ERR" | grep -q 'command not found' \
  && ok "and the reason names the invalid input, not an internal error: nothing that was captured is run as a command" || fail "invalid input was reported as an internal error: $OUT / stderr: $ERR"
RW_INTERNAL="$(RW_HOOK=x RW_ON_CRASH=deny bash -c 'source hooks/lib.sh; false' 2>&1 || true)"
printf '%s' "$RW_INTERNAL" | grep -q 'internal error at line' && ok "while a failure of the hook itself is still called an internal error, with its line" || fail "an internal error lost its name: $RW_INTERNAL"
# An event read only IN PART is not read. The first form of the fix above swallowed the failure of
# the parse and took any output for a parsed event; when the parse died on a later field, the
# fields already printed were kept and the rest read as empty -- so a guard saw a Bash call with no
# command and let it through (cold review of the 0.7.1 diff, 2026-10-01, measured with a command
# carrying a lone surrogate, which is valid JSON and cannot be written as text). The guard below
# refuses this command on its own when it can read it.
RW_PART='{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"s","cwd":"/tmp","tool_input":{"command":"git commit --trailer \"X: y\" -m \"a \ud800\""}}'
run_hook guard-commit "$RW_PART"
denied && printf '%s' "$OUT" | grep -q 'could not be read' && ! printf '%s' "$OUT" | grep -q 'not JSON' \
  && ok "a guard handed an event it can read only in part → DENY, and the reason says the event could not be read" || fail "a guard passed an event it could only read in part (rc=$RC out=$OUT)"
run_hook principles "$RW_PART"
[ "$RC" -eq 1 ] && [ -z "$OUT" ] && ok "and a context hook handed the same event → exit 1 notice, nothing injected from half an event" || fail "a context hook went on with half an event (rc=$RC out=$OUT)"
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
