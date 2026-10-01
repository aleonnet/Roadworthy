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
# The Portuguese words agree in gender and number. "Metade do conserto está pronta e testada" is a
# finished claim about half a fix; with only the masculine singular in the enumeration it was never
# judged (field, 2026-09-14, another project).
for claim in "Metade do conserto está pronta e testada." "As duas partes estão concluídas." "Tarefas finalizadas." "Entregues as três frentes."; do
  sgh "{\"session_id\":\"h3-$RANDOM\",\"cwd\":\"$SGH\",\"last_assistant_message\":\"$claim\"}"
  [ "$SGRC" -eq 2 ] || fail "a Portuguese claim with feminine or plural agreement was not judged: $claim"
done
ok "pronta, concluídas, finalizadas and entregues are finished claims too"
sgh "{\"session_id\":\"h4-$RANDOM\",\"cwd\":\"$SGH\",\"last_assistant_message\":\"O prontuário e o entregador estão na lista.\"}"
[ "$SGRC" -ne 2 ] && ok "and words that merely start the same way (prontuário, entregador) are not" || fail "the agreement forms over-matched: $SGERR"
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

# ── 0.7.0: a claim, not a word ────────────────────────────────────────────────
# 86 of 177 real blocks on this machine had the shape of a false positive: the word in a table row,
# negated, in "ready to", or in a tail that listed what was still open (measured 2026-09-30).
section "stop-gate (a claim that the work is finished, not a word in a report)"
SC="$TMP/stop-claim"; SCD="$TMP/stop-claim-data"; mkdir -p "$SC/.roadworthy" "$SCD"
git -C "$SC" init -q; git -C "$SC" config user.email t@t; git -C "$SC" config user.name t
printf 'true\n' > "$SC/.roadworthy/gates"; echo x > "$SC/f"; git -C "$SC" add -A; git -C "$SC" commit -q -m base
sc() {  # sc <session> <final message> [<extra env>]  -> SCRC
  set +e
  python3 -c 'import json,sys; print(json.dumps({"session_id":sys.argv[1],"cwd":sys.argv[2],"last_assistant_message":sys.argv[3]}))' "$1" "$SC" "$2" \
    | ROADWORTHY_DATA="$SCD" bash "$ROOT/hooks/run-hook.cmd" stop-gate >/dev/null 2>"$TMP/sc.err"
  SCRC=$?
  set -e
}
n=0
while IFS= read -r msg; do
  n=$((n + 1)); sc "r$n" "$(printf '%b' "$msg")"
  [ "$SCRC" -ne 2 ] || fail "a status report was blocked as a finished claim: $msg"
done <<'MSGS'
| 3 | the reader | table of cases | done |\n| 4 | the gate | not started | - |
The front is not done: two phases are left.
Ainda não está pronto; falta a bancada.
The branch is ready to be reviewed once the suite passes, not before.
Fica pronto para o fecho quando os portões passarem.
✅ feito e provado aqui · 🟡 feito no código e nos testes · ⬜ não começado · 📍 depende de você\nNothing is finished yet.
Phase 2 is done.\n⬜ Phase 3 has not started.
The reader is done; TODO: the gate and the closing.
Nada foi concluído nesta rodada.
MSGS
ok "a table row, a negation, 'ready to', 'pronto para', a legend and a tail that names an open item are not blocked ($n messages)"
n=0
while IFS= read -r msg; do
  n=$((n + 1)); sc "c$n" "$(printf '%b' "$msg")"
  [ "$SCRC" -eq 2 ] || fail "a finished claim on gates never measured passed: $msg (rc=$SCRC)"
done <<'MSGS'
All done.
The work is finished and pushed.
Está tudo pronto.
A frente foi concluída.
STATUS: passed
✅ feito e provado aqui · 🟡 feito no código · ⬜ não começado · 📍 depende de você\nTudo entregue.
MSGS
ok "a plain claim is still blocked, in both languages, with or without a legend above it ($n messages)"
set +e
python3 -c 'import json,sys; print(json.dumps({"session_id":"m1","cwd":sys.argv[1],"last_assistant_message":"Phase 2 is done.\nPENDING: phase 3."}))' "$SC" \
  | ROADWORTHY_DATA="$SCD" CLAUDE_PLUGIN_OPTION_STOP_GATE_OPEN_MARKERS="PENDING" bash "$ROOT/hooks/run-hook.cmd" stop-gate >/dev/null 2>&1
MRC=$?
set -e
[ "$MRC" -ne 2 ] && ok "stop_gate_open_markers names the project's own marks" || fail "the open-markers option was ignored"

# ── 0.7.0: the gates of every repository the turn wrote in ───────────────────
section "stop-gate (another repository the session wrote in)"
SA="$TMP/stop-a"; SB="$TMP/stop-b"; PD="$TMP/stop-plugin-data"; mkdir -p "$SA" "$SB/.roadworthy" "$SB/src" "$PD"
for r in "$SA" "$SB"; do git -C "$r" init -q; git -C "$r" config user.email t@t; git -C "$r" config user.name t; echo x > "$r/f"; done
SB="$(cd "$SB" && pwd -P)"; SA="$(cd "$SA" && pwd -P)"
printf 'true\n' > "$SB/.roadworthy/gates"; printf 'src/**\n' > "$SB/.roadworthy/scope"
git -C "$SA" add -A; git -C "$SA" commit -q -m base; git -C "$SB" add -A; git -C "$SB" commit -q -m base
sab() { set +e; python3 -c 'import json,sys; print(json.dumps({"session_id":"ab","cwd":sys.argv[1],"last_assistant_message":"All done."}))' "$SA" | env -u ROADWORTHY_DATA CLAUDE_PLUGIN_DATA="$PD" bash "$ROOT/hooks/run-hook.cmd" stop-gate >/dev/null 2>"$TMP/sab.err"; SABRC=$?; set -e; }
sab
[ "$SABRC" -ne 2 ] && ok "a session in a repository with no gates, that touched nothing else, is not blocked" || fail "blocked with nothing to answer for"
python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","session_id":"ab","cwd":sys.argv[1],"tool_input":{"file_path":sys.argv[2]+"/src/x.py"}}))' "$SA" "$SB" \
  | env -u ROADWORTHY_DATA CLAUDE_PLUGIN_DATA="$PD" bash "$ROOT/hooks/run-hook.cmd" rite-gate >/dev/null
sab
[ "$SABRC" -eq 2 ] && grep -q "$SB" "$TMP/sab.err" && ok "after an edit in ANOTHER repository, its gates are asked for, and it is named" || fail "the gates of the repository touched were not read (rc=$SABRC): $(cat "$TMP/sab.err")"
[ ! -e "$SA/.roadworthy" ] && [ -f "$PD/sessions/ab.touched" ] && ok "the note of what was touched lives with the plugin, not in either project" || fail "the touched-repositories note was written into a project"

rw_end
