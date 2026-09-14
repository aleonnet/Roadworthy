#!/usr/bin/env bash
# stop-gate
# Run alone: bash tests/hooks/stop-gate.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── stop-gate: "done" does not pass on stale gates ──────────────────────────
section "stop-gate"
# Exit 2 is what blocks a turn, and the reason goes to stderr -- the Stop event has its own
# contract, opposite to every other hook here.
SG="$TMP/stop"; SGD="$TMP/stopdata"; mkdir -p "$SG/.roadworthy" "$SGD"
git -C "$SG" init -q; git -C "$SG" config user.email t@t; git -C "$SG" config user.name t
echo x > "$SG/f"; git -C "$SG" add -A; git -C "$SG" commit -q -m base
sg() {  # sg <session> <final message>  -> SGRC, SGERR
  set +e
  printf '{"session_id":"%s","cwd":"%s","last_assistant_message":"%s"}' "$1" "$SG" "$2" \
    | ROADWORTHY_DATA="$SGD" bash "$ROOT/hooks/run-hook.cmd" stop-gate >/dev/null 2>"$TMP/sg.err"
  SGRC=$?
  set -e
  SGERR="$(cat "$TMP/sg.err")"
}
# Without a gates file it must NEVER block: close.sh --check fails there by design, and blocking
# on that would be a false positive in nearly every project.
sg noGates "All done."
[ "$SGRC" -ne 2 ] && ok "no gates declared: the turn is never blocked" || fail "blocked a project with no gates declared"
printf 'true\n' > "$SG/.roadworthy/gates"; git -C "$SG" add -A; git -C "$SG" commit -q -m gates
# Claiming completion with a gate that was never measured.
sg s1 "All done."
[ "$SGRC" -eq 2 ] && ok "a finished claim on gates that were never measured is blocked (exit 2)" || fail "stale gates passed: rc=$SGRC $SGERR"
printf '%s' "$SGERR" | grep -q 'MISSING' && ok "and the block shows the state of each gate" || fail "the block did not show the gate states: $SGERR"
# Not blocked twice on the same tree: a wall that repeats is a loop.
sg s1 "All done."
[ "$SGRC" -ne 2 ] && ok "the same tree is not blocked twice in a session" || fail "the latch did not hold: a blocked turn loops"
# A changed tree is blocked again: the latch is not a single shot.
echo y >> "$SG/f"; git -C "$SG" commit -qam changed
sg s1 "All done."
[ "$SGRC" -eq 2 ] && ok "a changed tree is blocked again (the latch is keyed on the tree, not the session)" || fail "the latch became a single shot"
# Saying nothing about being finished is not a claim.
sg s2 "Here is what I found so far; two things are still open."
[ "$SGRC" -ne 2 ] && ok "a turn that does not claim completion is never blocked" || fail "blocked an honest report"
# With the gates actually measured on this tree, the claim passes -- in a session that has never
# been latched, so the pass is the gates and not the latch.
(cd "$SG" && ROADWORTHY_DATA="$SGD" bash "$ROOT/skills/close/scripts/close.sh") >/dev/null 2>&1 || true
sg fresh "All done."
[ "$SGRC" -ne 2 ] && ok "with every gate FRESH the claim passes, in a session with no latch" || fail "fresh gates still blocked: $SGERR"
# Fails open, by declaration: no repository, no message, no transcript.
NOGIT2="$TMP/nogit-stop"; mkdir -p "$NOGIT2"
set +e
printf '{"session_id":"s3","cwd":"%s","last_assistant_message":"All done."}' "$NOGIT2" \
  | ROADWORTHY_DATA="$SGD" bash "$ROOT/hooks/run-hook.cmd" stop-gate >/dev/null 2>&1
[ $? -ne 2 ] && ok "outside a git repository it never blocks" || fail "blocked outside a repository"
printf '{"session_id":"s4","cwd":"%s"}' "$SG" | ROADWORTHY_DATA="$SGD" bash "$ROOT/hooks/run-hook.cmd" stop-gate >/dev/null 2>&1
[ $? -ne 2 ] && ok "with no final message and no transcript it never blocks" || fail "blocked with nothing to read"
CLAUDE_PLUGIN_OPTION_STOP_GATE=false bash -c 'printf "{\"session_id\":\"s5\",\"cwd\":\"'"$SG"'\",\"last_assistant_message\":\"All done.\"}" | ROADWORTHY_DATA="'"$SGD"'" bash "'"$ROOT"'/hooks/run-hook.cmd" stop-gate' >/dev/null 2>&1
[ $? -ne 2 ] && ok "stop_gate=false honoured" || fail "stop_gate=false ignored"
set -e

rw_end
