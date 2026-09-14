#!/usr/bin/env bash
# close
# Run alone: bash tests/scripts/close.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── close.sh: gates, evidence, FRESH/STALE, states ──────────────────────────
section "close.sh"
export ROADWORTHY_DATA="$TMP/rwdata"
CF="$TMP/close-repo"; fx_docs_tree_committed "$CF"
printf 'true\n' > "$CF/.roadworthy/gates"; printf 'docs/**\n' > "$CF/.roadworthy/scope"
rc=0; (cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh") > "$TMP/close1.log" 2>&1 || rc=$?
[ $rc -eq 1 ] && grep -q 'dirty' "$TMP/close1.log" && ok "dirty tree refused (gates untracked)" || fail "dirty tree accepted"
git -C "$CF" add -A; git -C "$CF" commit -q -m gates
(cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh") > "$TMP/close2.log" 2>&1 && ok "green gate → passed" || { fail "green gate failed"; cat "$TMP/close2.log"; }
[ ! -f "$CF/.roadworthy/scope" ] && [ "$(cat "$ROADWORTHY_DATA/state")" = "passed" ] && ok "scope released, state passed" || fail "scope/state after pass"
# The state is written in BOTH places: the shared data directory may belong to another project,
# and reporting "passed" for a front full of gaps is how a resume lies to the next session.
[ "$(cat "$CF/.roadworthy/state")" = "passed" ] && ok "the state is recorded in the project too" || fail "project state: $(cat "$CF/.roadworthy/state" 2>&1)"
# Discriminating on purpose: the two copies are made to DISAGREE, so the assertion can only pass
# by reading the project one. With both saying "passed" it passed either way and measured
# nothing -- caught by planting the defect.
printf 'needs_human\n' > "$ROADWORTHY_DATA/state"
[ "$( (cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh" --state) )" = "passed" ] && ok "--state reads the project copy, not the shared one" || fail "--state read the wrong copy"
printf 'passed\n' > "$ROADWORTHY_DATA/state"
# A gate that cannot go red is a green light, not a measurement. It warns; what refuses is that
# every gate has to come from the plan.
CLOSE_OUT="$( (cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh" --check) 2>&1 || true )"
printf '%s' "$CLOSE_OUT" | grep -q 'cannot fail' && ok "a gate that cannot fail is named, not silently accepted" || fail "trivial gate accepted in silence: $CLOSE_OUT"
CHK="$( (cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh" --check) 2>&1 )"
printf '%s' "$CHK" | grep -q 'FRESH     true' && ok "--check reports FRESH on the same tree" || fail "not FRESH; --check said: $CHK"
echo y >> "$CF/docs/README.md"
CHK="$( (cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh" --check) 2>&1 || true )"
printf '%s' "$CHK" | grep -q 'STALE' && ok "--check reports STALE after an edit" || fail "not STALE after edit; --check said: $CHK"
git -C "$CF" checkout -q -- docs/README.md
printf 'false\n' > "$CF/.roadworthy/gates"; printf 'docs/**\n' > "$CF/.roadworthy/scope"; git -C "$CF" add -A; git -C "$CF" commit -q -m red
! (cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh") >/dev/null 2>&1 && [ -f "$CF/.roadworthy/scope" ] && [ "$(cat "$ROADWORTHY_DATA/state")" = "gaps_found" ] && ok "red gate → gaps_found, scope kept" || fail "red gate handling"
(cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh" --needs-human "device bench") >/dev/null && [ "$(cat "$ROADWORTHY_DATA/state")" = "needs_human" ] && ok "--needs-human records the state" || fail "needs_human"
# Nothing measured is not "everything fresh". --check used to print the absence and exit 0, which
# is what let a night close claiming every gate FRESH with zero gates (measured 2026-09-13 on this
# repository, which had no .roadworthy/gates at all and a scope six days past its front).
NG="$TMP/nogates"; mkdir -p "$NG/.roadworthy"; git -C "$NG" init -q
(cd "$NG" && printf 'x\n' > f && git -c user.email=t@t -c user.name=t add -A && git -c user.email=t@t -c user.name=t commit -q -m base)
! (cd "$NG" && ROADWORTHY_DATA="$TMP/ngdata" bash "$ROOT/skills/close/scripts/close.sh" --check) >/dev/null 2>&1 && ok "--check without a gates file fails" || fail "--check passed with no gates file"
printf '# only a comment\n\n' > "$NG/.roadworthy/gates"; printf 'f\n' > "$NG/.roadworthy/scope"
git -C "$NG" -c user.email=t@t -c user.name=t add -A; git -C "$NG" -c user.email=t@t -c user.name=t commit -q -m gates
! (cd "$NG" && ROADWORTHY_DATA="$TMP/ngdata" bash "$ROOT/skills/close/scripts/close.sh" --check) >/dev/null 2>&1 && ok "--check on a gates file that declares none fails" || fail "--check passed with zero declared gates"
! (cd "$NG" && ROADWORTHY_DATA="$TMP/ngdata" bash "$ROOT/skills/close/scripts/close.sh") >/dev/null 2>&1 && [ -f "$NG/.roadworthy/scope" ] && ok "close with zero declared gates fails and keeps the scope" || fail "close released the scope with nothing measured"
unset ROADWORTHY_DATA

rw_end
