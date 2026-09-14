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
# A front the rite opened cannot lose its snapshot and still close. Removing plan.snapshot used to
# send the closing down the "no snapshot" path, which skipped the digests AND the check of files
# touched outside the globs -- the one act that turned a shell write outside the scope into a front
# closed `passed`, with nothing STALE because the fingerprint excludes the snapshot. The scope the
# rite writes names its plan in its first line; that is what tells this apart from a hand-written
# scope, which has no snapshot to lose (the case above, and every evaluation scaffold).
OR="$TMP/orphan"; fx_repo_committed "$OR"
printf '.roadworthy/scope\n.roadworthy/plan.snapshot\n.roadworthy/state\n.roadworthy/evidence.jsonl\n.roadworthy/denials.jsonl\n' > "$OR/.gitignore"
fx_front_rite "$OR" 'f' 'true'
git -C "$OR" add -A; git -C "$OR" commit -q -m 'front open'
rm "$OR/.roadworthy/plan.snapshot"
OR_OUT="$( (cd "$OR" && bash "$ROOT/skills/close/scripts/close.sh") 2>&1 || true )"
printf '%s' "$OR_OUT" | grep -q 'written by the rite' && [ -f "$OR/.roadworthy/scope" ] \
  && ok "a rite scope whose snapshot is gone refuses the closing, naming the snapshot" || fail "an orphan scope closed the front: $OR_OUT"
[ "$(cat "$OR/.roadworthy/state")" = "gaps_found" ] && ok "and records gaps_found, so the next front is blocked until someone looks" || fail "orphan closing left state: $(cat "$OR/.roadworthy/state" 2>&1)"
OR_CHK="$( (cd "$OR" && bash "$ROOT/skills/close/scripts/close.sh" --check) 2>&1 || true )"
printf '%s' "$OR_CHK" | grep -q 'written by the rite' && ok "--check says so too, which is what the stop gate reads" || fail "an orphan scope passed --check: $OR_CHK"
fx_front_rite "$OR" 'f' 'true'
(cd "$OR" && bash "$ROOT/skills/close/scripts/close.sh") >/dev/null 2>&1 \
  && ok "reopened from the plan, the same front closes (the refusal measures the missing snapshot, not the weather)" || fail "reopened front still refused"
# The 13:33 case at this script's own door. Evidence measured by a person's shell (no variable at
# all) has to be FRESH to a --check run the way a hook runs, with CLAUDE_PLUGIN_DATA set and nothing
# else: that variable is per plugin and shared by every project, and resolving the ledger through
# it is exactly what reported six FRESH gates as MISSING.
HK="$TMP/hookenv"; fx_repo_committed "$HK"; mkdir -p "$HK/.roadworthy"
printf 'true\n' > "$HK/.roadworthy/gates"; git -C "$HK" add -A; git -C "$HK" commit -q -m gates
(cd "$HK" && env -u ROADWORTHY_DATA bash "$ROOT/skills/close/scripts/close.sh") >/dev/null 2>&1 || true
HK_CHK="$( (cd "$HK" && env -u ROADWORTHY_DATA CLAUDE_PLUGIN_DATA="$TMP/hookplugin" bash "$ROOT/skills/close/scripts/close.sh" --check) 2>&1 || true )"
printf '%s' "$HK_CHK" | grep -q 'FRESH     true' \
  && ok "evidence measured by a plain shell is FRESH to a --check run with only CLAUDE_PLUGIN_DATA set" || fail "close.sh looked for the ledger in the shared plugin directory: $HK_CHK"
# The plan's second home is inside the repository (docs/plans, the house norm). A plan written
# there is a new file the front did not declare -- it cannot declare itself before it exists --
# and the out-of-scope check named it and refused the closing. The snapshot knows which file the
# front came from; that one file is the rite's own and never stray.
PH="$TMP/planhome"; fx_repo_committed "$PH"; mkdir -p "$PH/docs/plans"
printf '.roadworthy/scope\n.roadworthy/plan.snapshot\n.roadworthy/state\n.roadworthy/evidence.jsonl\n.roadworthy/denials.jsonl\n' > "$PH/.gitignore"
git -C "$PH" add -A; git -C "$PH" commit -q -m ignore
printf '# P\n## Escopo\n```\nf\n```\n## Verificação\n```\ntrue\n```\n' > "$PH/docs/plans/2026-01-01-0900-p.md"
(cd "$PH" && bash "$ROOT/skills/plan/scripts/scope-write.sh" docs/plans/2026-01-01-0900-p.md) >/dev/null
git -C "$PH" add -A; git -C "$PH" commit -q -m 'front open, plan inside the repository'
PH_OUT="$( (cd "$PH" && env -u ROADWORTHY_DATA bash "$ROOT/skills/close/scripts/close.sh") 2>&1 || true )"
printf '%s' "$PH_OUT" | grep -q '^close: passed' \
  && ok "the front's own plan, inside the repository, is not counted as a stray file" || fail "the closing named the front's own plan as stray: $PH_OUT"
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
