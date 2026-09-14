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
# THE FIELD CASE OF 2026-09-14, 13:33. Claude Code hands every hook CLAUDE_PLUGIN_DATA, a directory
# per plugin and shared by every project on the machine; a person's shell does not set it. The gates
# below are measured in the shell, the way a person measures them, and the hook then runs the way
# the harness runs it. Six FRESH gates came back MISSING that afternoon, because the hook looked for
# the ledger where its environment pointed and the evidence was in the project.
SGH="$TMP/stophook"; SGP="$TMP/plugindata"; mkdir -p "$SGH/.roadworthy" "$SGP"
git -C "$SGH" init -q; git -C "$SGH" config user.email t@t; git -C "$SGH" config user.name t
printf 'true\n' > "$SGH/.roadworthy/gates"; echo x > "$SGH/f"; git -C "$SGH" add -A; git -C "$SGH" commit -q -m base
(cd "$SGH" && bash "$ROOT/skills/close/scripts/close.sh") >/dev/null 2>&1 || true
sgh() {  # sgh <event json> -> SGRC, SGERR; ROADWORTHY_DATA unset, CLAUDE_PLUGIN_DATA set, as in the harness
  set +e
  printf '%s' "$1" | CLAUDE_PLUGIN_DATA="$SGP" bash "$ROOT/hooks/run-hook.cmd" stop-gate >/dev/null 2>"$TMP/sgh.err"
  SGRC=$?
  set -e
  SGERR="$(cat "$TMP/sgh.err")"
}
sgh "{\"session_id\":\"h1\",\"cwd\":\"$SGH\",\"last_assistant_message\":\"All done.\"}"
[ "$SGRC" -ne 2 ] && ok "gates measured in the shell are FRESH to the hook too, with CLAUDE_PLUGIN_DATA set (the 13:33 case)" || fail "fresh gates blocked from the hook environment: $SGERR"
# And when it does block, the latch lands in the project, where the next `--check` from a shell or
# a hook both find it -- not in the shared plugin directory, which is per plugin, not per project.
echo y >> "$SGH/f"; git -C "$SGH" commit -qam changed
sgh "{\"session_id\":\"h1\",\"cwd\":\"$SGH\",\"last_assistant_message\":\"All done.\"}"
[ "$SGRC" -eq 2 ] && [ -d "$SGH/.roadworthy/stop-latch" ] && [ ! -d "$SGP/stop-latch" ] \
  && ok "a block writes its latch in the project's .roadworthy, not in the shared plugin directory" || fail "the latch went to the shared plugin directory (rc=$SGRC)"
# `stop_hook_active` is documented: "Claude Code overrides a Stop hook after it blocks eight times
# in a row without progress ... Parse the stop_hook_active field from the JSON input and exit early
# if it's true". Honouring it is cheaper than waiting for the override.
echo z >> "$SGH/f"; git -C "$SGH" commit -qam changed-again
sgh "{\"session_id\":\"h2\",\"cwd\":\"$SGH\",\"last_assistant_message\":\"All done.\",\"stop_hook_active\":true}"
[ "$SGRC" -ne 2 ] && ok "stop_hook_active: true is honoured and the turn is never blocked" || fail "stop_hook_active ignored: $SGERR"
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
