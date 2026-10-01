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

# ── 0.7.0: the closing tells the truth ───────────────────────────────────────
section "close.sh (every declared gate runs, and its evidence is kept)"
CLOSE="$ROOT/skills/close/scripts/close.sh"
# A gate inherited the loop's standard input, which is the gates file itself. Measured in the field
# on 2026-09-24: nine gates declared, the seventh an `ssh`, which read the two lines after it; the
# loop met end of file, nothing had failed, and the front closed `passed` with two gates never run.
SI="$TMP/stdin-gate"; fx_repo_committed "$SI"; mkdir -p "$SI/.roadworthy"
printf 'cat >/dev/null\nfalse\n' > "$SI/.roadworthy/gates"; printf 'f\n' > "$SI/.roadworthy/scope"
git -C "$SI" add -A; git -C "$SI" commit -q -m gates
SI_OUT="$( (cd "$SI" && bash "$CLOSE") 2>&1 || true )"
# The assertion is that the SECOND gate ran and failed -- not merely that the closing refused,
# which the count of gates below would also catch.
printf '%s' "$SI_OUT" | grep -q 'FAIL  false' && printf '%s' "$SI_OUT" | grep -q '1 gate(s) red' && [ -f "$SI/.roadworthy/scope" ] \
  && ok "a gate that reads its standard input does not swallow the gates after it" || fail "a gate that reads stdin hid the gates after it: $SI_OUT"
# The whole output of a gate was handed to python3 as an ARGUMENT. Above the system's limit the
# record is never written -- `python3: Argument list too long` in the field on 2026-09-22, with a
# suite of 3,896 tests -- so the gate passes on the screen and is MISSING to the next --check.
BG="$TMP/big-gate"; fx_repo_committed "$BG"; mkdir -p "$BG/.roadworthy"
printf '%s\n' "python3 -c \"import sys; sys.stdout.write('x' * 3000000)\"" > "$BG/.roadworthy/gates"; printf 'f\n' > "$BG/.roadworthy/scope"
git -C "$BG" add -A; git -C "$BG" commit -q -m gates
(cd "$BG" && bash "$CLOSE") > "$TMP/big.log" 2>&1 || true
BG_CHK="$( (cd "$BG" && bash "$CLOSE" --check) 2>&1 || true )"
printf '%s' "$BG_CHK" | grep -q 'FRESH     python3' \
  && ok "a gate that prints three megabytes still leaves its evidence, and --check says FRESH" || fail "a large gate output left no evidence: $BG_CHK $(tail -2 "$TMP/big.log")"
# Defence in depth for the first case: whatever makes the loop stop early, the number of gates that
# ran has to be the number declared. Here a gate empties the list while the closing is reading it.
TG="$TMP/trunc-gate"; fx_repo_committed "$TG"; mkdir -p "$TG/.roadworthy"
printf ': > .roadworthy/gates\nfalse\n' > "$TG/.roadworthy/gates"; printf 'f\n' > "$TG/.roadworthy/scope"
git -C "$TG" add -A; git -C "$TG" commit -q -m gates
TG_OUT="$( (cd "$TG" && bash "$CLOSE") 2>&1 || true )"
printf '%s' "$TG_OUT" | grep -q '2 gate(s) declared, 1 ran' && [ -f "$TG/.roadworthy/scope" ] \
  && ok "a closing whose loop stopped early is refused, saying how many were declared and how many ran" || fail "the closing passed with gates that never ran: $TG_OUT"

section "close.sh (human verification has a state of its own)"
# The state was ONE word, rewritten by every closing. Measured in the field on 2026-09-30: three
# items waiting for a person at 18:28, a documentation front closed at 19:55 and wrote `passed`
# over them; one was never checked. And there was no way to record the answer at all.
HU="$TMP/human"; fx_repo_committed "$HU"; mkdir -p "$HU/.roadworthy"
printf 'true\n' > "$HU/.roadworthy/gates"; printf 'f\n' > "$HU/.roadworthy/scope"
git -C "$HU" add -A; git -C "$HU" commit -q -m gates
(cd "$HU" && bash "$CLOSE" --needs-human "bench 3 on the device") >/dev/null
(cd "$HU" && bash "$CLOSE" --needs-human "bench 3 on the device") >/dev/null     # said twice: one item
HU_OUT="$( (cd "$HU" && bash "$CLOSE") 2>&1 || true )"
[ "$( (cd "$HU" && bash "$CLOSE" --state) )" = "needs_human" ] && printf '%s' "$HU_OUT" | grep -q 'bench 3 on the device' && [ ! -f "$HU/.roadworthy/scope" ] \
  && ok "a green closing does not erase a pending human verification: the state stays needs_human and the item is named" || fail "a later closing erased the pending human verification: $HU_OUT"
[ "$( (cd "$HU" && bash "$CLOSE" --human) | grep -c 'bench 3')" = "1" ] && ok "the same item said twice is one item" || fail "a repeated item counted twice: $( (cd "$HU" && bash "$CLOSE" --human) )"
! (cd "$HU" && bash "$CLOSE" --human "no such item" approved --by owner) >/dev/null 2>&1 && ok "a verdict on an item nobody opened is refused" || fail "a verdict on an unknown item was accepted"
! (cd "$HU" && bash "$CLOSE" --human "bench 3 on the device" approved) >/dev/null 2>&1 && ok "a verdict with nobody named is refused (--by)" || fail "an anonymous verdict was accepted"
(cd "$HU" && bash "$CLOSE" --human "bench 3 on the device" approved --by owner) >/dev/null
[ "$( (cd "$HU" && bash "$CLOSE" --state) )" = "passed" ] && [ -z "$( (cd "$HU" && bash "$CLOSE" --human) | grep 'bench 3' || true)" ] \
  && ok "an approved verdict closes the item, and the state goes back to what the closing measured" || fail "the human verdict was not recorded: state $( (cd "$HU" && bash "$CLOSE" --state) )"
(cd "$HU" && bash "$CLOSE" --needs-human "colour bands") >/dev/null
(cd "$HU" && bash "$CLOSE" --human "colour bands" rejected --by owner --note "wrong hue") >/dev/null
[ "$( (cd "$HU" && bash "$CLOSE" --state) )" = "gaps_found" ] && [ "$(cat "$HU/.roadworthy/state")" = "gaps_found" ] \
  && ok "a rejected verdict records gaps_found: the work is reopened, not forgotten" || fail "the human verdict was not recorded: a rejection left state $( (cd "$HU" && bash "$CLOSE" --state) )"
# A record written by 0.6.2 has no kind and no id: it is still an item waiting for someone.
python3 -c 'import json,sys
open(sys.argv[1],"a").write(json.dumps({"ts":"2026-09-30T18:28:00","head":"x","wtree":"x","cmd":"needs-human: legacy item","cmd_sha256":"x","exit":0,"tail":"legacy item"})+"\n")' "$ROADWORTHY_DATA/evidence.jsonl"
LG="$( (cd "$HU" && bash "$CLOSE" --human) )"
printf '%s' "$LG" | grep -q 'legacy item' && ok "an item recorded by 0.6.2 is read back as open" || fail "a 0.6.2 needs-human record was ignored: $LG"
(cd "$HU" && bash "$CLOSE" --human all approved --by owner) >/dev/null
[ -z "$( (cd "$HU" && bash "$CLOSE" --human) | grep -v '^close: no human' || true)" ] && ok "--human all closes every open item at once" || fail "--human all left items open: $( (cd "$HU" && bash "$CLOSE" --human) )"
# A front with no way forward has an exit that is recorded, never a silent one.
AB="$TMP/abandon"; fx_repo_committed "$AB"; mkdir -p "$AB/.roadworthy"
printf 'false\n' > "$AB/.roadworthy/gates"; printf 'f\n' > "$AB/.roadworthy/scope"
git -C "$AB" add -A; git -C "$AB" commit -q -m gates
# Run the way a project runs: its own ledger, inside it.
! (cd "$AB" && env -u ROADWORTHY_DATA bash "$CLOSE" --abandon) >/dev/null 2>&1 && [ -f "$AB/.roadworthy/scope" ] && ok "abandoning a front needs a reason" || fail "a front was abandoned with no reason"
(cd "$AB" && env -u ROADWORTHY_DATA bash "$CLOSE" --abandon "the approach was wrong; replanning") >/dev/null
[ ! -f "$AB/.roadworthy/scope" ] && [ "$( (cd "$AB" && env -u ROADWORTHY_DATA bash "$CLOSE" --state) )" = "gaps_found" ] && grep -q 'the approach was wrong' "$AB/.roadworthy/evidence.jsonl" \
  && ok "an abandoned front releases the scope, records the reason and leaves gaps_found" || fail "abandon did not record: state $( (cd "$AB" && env -u ROADWORTHY_DATA bash "$CLOSE" --state) )"
# A project's own ledger is the project's whatever its path is today: renaming the directory must
# not drop what is waiting for a person.
MV="$TMP/moved-a"; fx_repo_committed "$MV"; mkdir -p "$MV/.roadworthy"; printf 'true\n' > "$MV/.roadworthy/gates"
git -C "$MV" add -A; git -C "$MV" commit -q -m gates
(cd "$MV" && env -u ROADWORTHY_DATA bash "$CLOSE" --needs-human "check the label") >/dev/null
mv "$MV" "$TMP/moved-b"
[ "$( (cd "$TMP/moved-b" && env -u ROADWORTHY_DATA bash "$CLOSE" --state) )" = "needs_human" ] \
  && ok "a pending item survives the repository being renamed" || fail "renaming the repository dropped a pending human verification"
unset ROADWORTHY_DATA

rw_end
