#!/usr/bin/env bash
# session-state
# Run alone: bash tests/hooks/session-state.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── session-state: what the rite left on disk, said at the first line ───────
# Every other hook is reactive, so state that expired in silence was found the hard way: a night
# marker left on for a day and a half surfaced when it denied a merge, and a scope left by the
# previous front denied 35 writes (field, 2026-09-22). This hook says the state when the session
# starts. It reports and never blocks: the SessionStart event cannot block, by the hooks reference.
section "session-state (SessionStart)"
SS="$TMP/ss"; fx_repo_committed "$SS"
git -C "$SS" branch -m trunk
ss() {  # ss <cwd> [source] -> OUT, RC, ERR; runs the way the harness runs a hook
  run_hook session-state "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s\",\"cwd\":\"$1\",\"source\":\"${2:-startup}\"}"
}
ss "$SS"
[ "$RC" -eq 0 ] && golden session-envelope.json && ok "inside a repository it answers in the golden envelope" || { fail "the session started blind: rc=$RC out=$OUT"; why; }
CTX="$(context)"
printf '%s' "$CTX" | grep -q 'branch     trunk @ ' && ok "it names the branch and the commit" || fail "the session started blind: no branch line: $CTX"
printf '%s' "$CTX" | grep -q 'tree       clean' && printf '%s' "$CTX" | grep -q 'front      none open' && printf '%s' "$CTX" | grep -q 'overnight  off' \
  && printf '%s' "$CTX" | grep -q 'gates      none declared' && ok "a repository with nothing of the rite says so, line by line" || fail "the session started blind: an empty repository was not described: $CTX"
printf '%s' "$CTX" | grep -q 'not a verdict' && ok "and says these are facts, not a verdict" || fail "the report does not say it is not a verdict"

# A front opened by the rite, with gates that were never measured.
printf '.roadworthy/scope\n.roadworthy/plan.snapshot\n.roadworthy/state\n.roadworthy/evidence.jsonl\n.roadworthy/denials.jsonl\n' > "$SS/.gitignore"
git -C "$SS" add -A; git -C "$SS" commit -q -m ignore
fx_front_rite "$SS" 'f' 'true'
git -C "$SS" add -A; git -C "$SS" commit -q -m 'front open'
ss "$SS" resume
CTX="$(context)"
printf '%s' "$CTX" | grep -q 'front      open from ss-rite-plan.md since ' && printf '%s' "$CTX" | grep -q '1 glob(s)' \
  && ok "an open front is named: the plan it came from, since when, how many globs" || fail "the session started blind: the open front was not named: $CTX"
printf '%s' "$CTX" | grep -q 'gates      1 declared: 1 MISSING' && ok "gates that were never measured are MISSING, counted" || fail "the gates line is wrong: $CTX"
printf '%s' "$CTX" | grep -q '(resume)' && ok "and it says how the session started" || fail "the source of the session is not shown: $CTX"
# The same reading from a subdirectory: the project's state lives at its root.
mkdir -p "$SS/deep/er"; ss "$SS/deep/er"
printf '%s' "$(context)" | grep -q 'front      open from ss-rite-plan.md' && ok "from a subdirectory it reads the project, not the directory" || fail "the session started blind from a subdirectory"
# Measured gates, a person waited for, and a night left on.
(cd "$SS" && bash "$ROOT/skills/close/scripts/close.sh" --needs-human "bench on the device") >/dev/null
(cd "$SS" && bash "$ROOT/skills/close/scripts/close.sh") >/dev/null 2>&1 || true
printf '{"started_iso":"2026-09-21T07:52:00Z","topic":"night"}\n' > "$SS/.roadworthy/overnight"
ss "$SS"
CTX="$(context)"
printf '%s' "$CTX" | grep -q 'gates      1 declared: 1 FRESH' && printf '%s' "$CTX" | grep -q 'front      none open' \
  && ok "after the closing: the front is closed and the gate is FRESH" || fail "the closed front was not described: $CTX"
printf '%s' "$CTX" | grep -q 'state      needs_human' && printf '%s' "$CTX" | grep -q 'waiting for a person: 1' && printf '%s' "$CTX" | grep -q 'bench on the device' \
  && ok "what is waiting for a person is counted and named" || fail "the pending human verification was not shown: $CTX"
printf '%s' "$CTX" | grep -q 'overnight  ON since 2026-09-21T07:52:00Z (night)' \
  && ok "a night marker left on is said with the hour it started" || fail "the night marker was not shown: $CTX"
rm -f "$SS/.roadworthy/overnight"
# A dirty tree is counted; the plugin's own bookkeeping is not part of the count.
echo y >> "$SS/f"; echo new > "$SS/untracked.txt"
ss "$SS"
printf '%s' "$(context)" | grep -q 'tree       2 file(s) changed or untracked' && ok "a dirty tree is counted, without the plugin's own files" || fail "the tree line is wrong: $(context)"
# A scope that declares nothing opens no front and locks every edit: said in those words.
: > "$SS/.roadworthy/scope"; ss "$SS"
printf '%s' "$(context)" | grep -q 'declares nothing' && ok "an empty scope file is called what it is" || fail "the empty scope was not named: $(context)"
rm -f "$SS/.roadworthy/scope"

# It is silent where it has nothing to say, and it never stands in the way.
NOGIT="$TMP/ss-nogit"; mkdir -p "$NOGIT"; ss "$NOGIT"
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "outside a git repository it says nothing" || fail "it spoke outside a repository: $OUT"
run_hook session-state 'not json'
[ "$RC" -eq 1 ] && [ -z "$OUT" ] && [ -n "$ERR" ] && ok "invalid input: a notice and exit 1, never a block (fails open)" || fail "session-state crash policy: rc=$RC out=$OUT"
CLAUDE_PLUGIN_OPTION_SESSION_STATE=false ss "$SS"
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "session_state=false honoured" || fail "session_state=false ignored"

# ── 0.7.0: what the owner requires, and a project that tracks the rite's local state ─────────
SR="$TMP/ss-rites"; mkdir -p "$SR/.roadworthy"; git -C "$SR" init -q; git -C "$SR" config user.email t@t; git -C "$SR" config user.name t
printf '# the owner\nplan_gate: both\ndiff_review: required\n' > "$SR/.roadworthy/rites"; printf 'src/**\n' > "$SR/.roadworthy/scope"
printf 'x\n' > "$SR/f"; git -C "$SR" add -A; git -C "$SR" commit -q -m 'everything, the scope too'
SRO="$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SessionStart","source":"startup","session_id":"s","cwd":sys.argv[1]}))' "$SR" | env -u ROADWORTHY_DATA bash "$ROOT/hooks/run-hook.cmd" session-state | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])')"
printf '%s' "$SRO" | grep -q 'the owner requires: plan_gate: both; diff_review: required' \
  && ok "the session starts knowing what the owner requires of this project" || fail "the session started blind to the owner's rites: $SRO"
printf '%s' "$SRO" | grep -q "local state is tracked by git" && ok "and is told when the rite's local state is tracked by git" || fail "a tracked scope was not said: $SRO"

rw_end
