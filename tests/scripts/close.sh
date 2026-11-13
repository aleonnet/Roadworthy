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
fx_owner_approval_off "$PH"
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
# What the first cold review of this script found (2026-09-30), each reproduced before its fix.
# A gates file whose last line has no newline: `read` returns non-zero on it and the loop dropped
# it, in the count and in the run alike -- so the two agreed, and the last gate never ran.
UT="$TMP/unterminated"; fx_repo_committed "$UT"; mkdir -p "$UT/.roadworthy"
printf 'true\nfalse' > "$UT/.roadworthy/gates"; printf 'f\n' > "$UT/.roadworthy/scope"
git -C "$UT" add -A; git -C "$UT" commit -q -m gates
UT_OUT="$( (cd "$UT" && env -u ROADWORTHY_DATA bash "$CLOSE") 2>&1 || true )"
printf '%s' "$UT_OUT" | grep -q 'FAIL  false' && [ -f "$UT/.roadworthy/scope" ] \
  && ok "the last gate runs even when the file does not end in a newline" || fail "the last gate, unterminated, never ran: $UT_OUT"
UT_CHK="$( (cd "$UT" && env -u ROADWORTHY_DATA bash "$CLOSE" --check) 2>&1 || true )"
printf '%s' "$UT_CHK" | grep -q 'FRESH-RED false' && ok "and --check reads it too" || fail "the last gate, unterminated, is invisible to --check: $UT_CHK"
# A project from before 0.7.0: the state file says needs_human, the ledger holds the item and the
# gates of the closing before it, and no record of how a closing ended. With the item approved the
# ledger used to say nothing, so the stale word stood: needs_human, with nothing open, for ever.
LS="$TMP/legacy-state"; fx_repo_committed "$LS"; mkdir -p "$LS/.roadworthy"; printf 'true\n' > "$LS/.roadworthy/gates"
git -C "$LS" add -A; git -C "$LS" commit -q -m gates
python3 -c 'import json,sys
rows = [{"ts":"2026-09-20T10:00:00","head":"h","wtree":"w1","cmd":"true","cmd_sha256":"x","exit":0,"tail":""},
        {"ts":"2026-09-20T10:01:00","head":"h","wtree":"w1","cmd":"needs-human: the label on the device","cmd_sha256":"x","exit":0,"tail":""}]
open(sys.argv[1],"w").write("".join(json.dumps(r)+"\n" for r in rows))' "$LS/.roadworthy/evidence.jsonl"
printf 'needs_human\n' > "$LS/.roadworthy/state"
(cd "$LS" && env -u ROADWORTHY_DATA bash "$CLOSE" --human all approved --by owner) >/dev/null
[ "$( (cd "$LS" && env -u ROADWORTHY_DATA bash "$CLOSE" --state) )" = "passed" ] && [ "$(cat "$LS/.roadworthy/state")" = "passed" ] \
  && ok "with every item approved, a project from before 0.7.0 goes back to what its last gates measured" || fail "an approved item left needs_human behind: state $( (cd "$LS" && env -u ROADWORTHY_DATA bash "$CLOSE" --state) ), file $(cat "$LS/.roadworthy/state")"
python3 -c 'import json,sys
open(sys.argv[1],"a").write(json.dumps({"ts":"2026-09-21T10:00:00","head":"h","wtree":"w2","cmd":"true","cmd_sha256":"x","exit":1,"tail":""})+"\n")' "$LS/.roadworthy/evidence.jsonl"
[ "$( (cd "$LS" && env -u ROADWORTHY_DATA bash "$CLOSE" --state) )" = "gaps_found" ] \
  && ok "and to gaps_found when those last gates were red" || fail "an approved item hid red gates: state $( (cd "$LS" && env -u ROADWORTHY_DATA bash "$CLOSE" --state) )"
# `--by` with nothing after it: `shift 2` fails with one argument left, shifts nothing, and the
# loop span for ever. The alarm is the assertion: a command that hangs is killed and counted.
BY_RC=0; (cd "$HU" && perl -e 'alarm 20; exec @ARGV' bash "$CLOSE" --human all approved --by) >/dev/null 2>&1 || BY_RC=$?
[ "$BY_RC" -eq 1 ] && ok "--by with no value is refused at once" || fail "--by with no value did not end in a refusal (exit $BY_RC; 142 is the alarm: it hung)"
# ── 0.7.0: the closing looks at what is protected, and at what the owner requires ────────────
PR="$TMP/protected-diff"; fx_repo_committed "$PR"; mkdir -p "$PR/.roadworthy" "$PR/lib/auth" "$PR/src" "$PR/notes"
printf 't\n' > "$PR/lib/auth/token.py"; printf 'a\n' > "$PR/src/a.py"
printf '# P\n## Scope\n```\nsrc/**\nlib/**\n```\n## Verification\n```\ntrue\n```\n' > "$PR/plan.md"
git -C "$PR" add -A; git -C "$PR" commit -q -m base
fx_owner_approval_off "$PR"
(cd "$PR" && bash "$ROOT/skills/plan/scripts/scope-write.sh" plan.md) >/dev/null
printf 'lib/auth/**\n' > "$PR/.roadworthy/protected"; printf 'notes/**\n' > "$PR/.roadworthy/free"
printf 't2\n' > "$PR/lib/auth/token.py"; printf 'n\n' > "$PR/notes/n.md"
git -C "$PR" add -A; git -C "$PR" commit -q -m 'a protected path changed, in scope'
PR_OUT="$( (cd "$PR" && env -u ROADWORTHY_DATA bash "$CLOSE") 2>&1 || true )"
printf '%s' "$PR_OUT" | grep -q 'protected path' && printf '%s' "$PR_OUT" | grep -q 'lib/auth/token.py' && [ -f "$PR/.roadworthy/scope" ] \
  && ok "a protected path in the front's diff refuses the closing, and is named" || fail "the closing passed over a protected path: $PR_OUT"
printf 't\n' > "$PR/lib/auth/token.py"; git -C "$PR" commit -q -am 'put back'
PR_OUT="$( (cd "$PR" && env -u ROADWORTHY_DATA bash "$CLOSE") 2>&1 || true )"
printf '%s' "$PR_OUT" | grep -q 'close: passed' \
  && ok "put back as it was, the front closes -- and a path the owner freed is not counted against it" || fail "a freed path, or a protected path put back, refused the closing: $PR_OUT"
# The owner's rites: a closing needs an approved review of the commit it closes.
RV="$TMP/review-required"; fx_repo_committed "$RV"; mkdir -p "$RV/.roadworthy"
printf 'true\n' > "$RV/.roadworthy/gates"; printf 'f\n' > "$RV/.roadworthy/scope"; printf 'diff_review: required\n' > "$RV/.roadworthy/rites"
git -C "$RV" add -A; git -C "$RV" commit -q -m gates
RV_OUT="$( (cd "$RV" && env -u ROADWORTHY_DATA bash "$CLOSE") 2>&1 || true )"
printf '%s' "$RV_OUT" | grep -q 'requires a review of the diff' && [ -f "$RV/.roadworthy/scope" ] && [ "$(cat "$RV/.roadworthy/state")" = "gaps_found" ] \
  && ok "with diff_review required and no verdict on record, green gates do not close the front" || fail "the closing passed without the review the project requires: $RV_OUT"
rv_event() { python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SubagentStop","session_id":"s","cwd":sys.argv[1],"agent_type":"roadworthy:cold-reviewer","last_assistant_message":sys.argv[2]}))' "$RV" "$1"; }
rv_event $'Two blockers.\n\nVERDICT: REJECTED' | env -u ROADWORTHY_DATA bash "$ROOT/hooks/run-hook.cmd" review-record
RV_OUT="$( (cd "$RV" && env -u ROADWORTHY_DATA bash "$CLOSE") 2>&1 || true )"
printf '%s' "$RV_OUT" | grep -q 'says REJECTED' && [ -f "$RV/.roadworthy/scope" ] \
  && ok "a REJECTED verdict recorded by the plugin keeps it open" || fail "the closing passed without the review the project requires (a rejected one): $RV_OUT"
rv_event $'Round 2: the blockers fell.\n\n**VERDICT: APPROVED**' | env -u ROADWORTHY_DATA bash "$ROOT/hooks/run-hook.cmd" review-record
RV_OUT="$( (cd "$RV" && env -u ROADWORTHY_DATA bash "$CLOSE") 2>&1 || true )"
printf '%s' "$RV_OUT" | grep -q 'diff review: APPROVED' && printf '%s' "$RV_OUT" | grep -q 'close: passed' \
  && ok "an APPROVED verdict for this commit, recorded when the reviewer finished, closes it" || fail "an approved review did not close the front (a dead end): $RV_OUT"
rv_event 'I looked around and everything seems fine.' | env -u ROADWORTHY_DATA bash "$ROOT/hooks/run-hook.cmd" review-record
[ "$(grep -c '"kind": "review"' "$RV/.roadworthy/evidence.jsonl")" = "2" ] \
  && ok "a subagent that ends with no verdict line records nothing" || fail "a report with no verdict was recorded as a review"
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

# ── 0.7.0: what a refused closing leaves behind, and a closing with nothing open ─────────────
RS="$TMP/refused-state"; fx_repo_committed "$RS"; mkdir -p "$RS/src"; printf 'a\n' > "$RS/src/a.py"
printf '# P\n## Scope\n```\nsrc/**\n```\n## Verification\n```\ntrue\n```\n' > "$RS/plan.md"
git -C "$RS" add -A; git -C "$RS" commit -q -m base
fx_owner_approval_off "$RS"
rs() { (cd "$RS" && env -u ROADWORTHY_DATA bash "$CLOSE" "$@") 2>&1 || true; }
(cd "$RS" && bash "$ROOT/skills/plan/scripts/scope-write.sh" plan.md) >/dev/null
git -C "$RS" check-ignore -q .roadworthy/scope && git -C "$RS" check-ignore -q .roadworthy/plan.snapshot && ! git -C "$RS" check-ignore -q .roadworthy/gates \
  && ok "opening a front makes the rite's local state ignored in this clone, and leaves the gates versioned" || fail "the rite's local state is still visible to git add -A"
[ -z "$(git -C "$RS" status --porcelain -- .gitignore)" ] && ok "without touching the project's own .gitignore" || fail "scope-write changed the project's .gitignore"
printf 'stray\n' > "$RS/outside.txt"; git -C "$RS" add -A; git -C "$RS" commit -q -m 'the gates, and a file outside the scope'
RS_OUT="$(rs)"
printf '%s' "$RS_OUT" | grep -q 'outside its declared scope' && [ "$(rs --state)" = "gaps_found" ] \
  && ok "a closing refused before the gates leaves gaps_found, not the word of the front before" || fail "a refused closing did not record gaps_found: $(rs --state) / $RS_OUT"
printf '%s' "$RS_OUT" | grep -q 'edit its Scope' && ok "and the refusal says how a scope is widened" || fail "the out-of-scope refusal does not say the way forward: $RS_OUT"
git -C "$RS" rm -q outside.txt; git -C "$RS" commit -q -m 'put back'
printf '%s' "$(rs)" | grep -q 'close: passed' && ok "put back, the same front closes" || fail "the front did not close after the stray file was removed"
printf 'h\n' > "$RS/handoff.md"; git -C "$RS" add -A; git -C "$RS" commit -q -m 'a hand-off, after the closing'
RS_OUT="$(rs)"
printf '%s' "$RS_OUT" | grep -q 'no front is open here' && [ "$(rs --state)" = "passed" ] \
  && ok "closing again with nothing open says so, and leaves the state alone" || fail "a closing with no front open spoke of a changed scope, or moved the state: $(rs --state) / $RS_OUT"
(cd "$RS" && bash "$ROOT/skills/plan/scripts/scope-write.sh" plan.md) >/dev/null 2>&1
printf 'dirt\n' >> "$RS/src/a.py"
RS_OUT="$(rs)"
printf '%s' "$RS_OUT" | grep -q 'the tree is dirty' && printf '%s' "$RS_OUT" | grep -q 'src/a.py' \
  && ok "a dirty tree is refused, and the refusal names what is not committed" || fail "the dirty-tree refusal does not name the path: $RS_OUT"
printf '%s' "$RS_OUT" | grep -q 'git stash' && fail "the dirty-tree refusal still tells the agent to stash somebody else's file: $RS_OUT" || ok "and nobody is told to stash a file that is not theirs"

# ── 0.8.0: what was already changed when the front opened does not block the closing ─────────
# The opening has recorded, since 0.7.0, every path outside the scope that was already changed,
# with its content (`preexisting` in the snapshot), and the fence that measures the tree leaves
# those alone. The closing did not read it: it refused the tree as dirty over the owner's own
# uncommitted file and told the agent to `git stash` it, and it counted every untracked file as
# touched by the front.
PX="$TMP/preexisting"; fx_repo_committed "$PX"; mkdir -p "$PX/src" "$PX/notes"
printf 'a\n' > "$PX/src/a.py"; printf 'n\n' > "$PX/notes.txt"
printf '# P\n## Scope\n```\nsrc/**\n```\n## Verification\n```\ntrue\n```\n' > "$TMP/px-plan.md"
git -C "$PX" add -A; git -C "$PX" commit -q -m base
fx_owner_approval_off "$PX"
px() { (cd "$PX" && env -u ROADWORTHY_DATA bash "$CLOSE") 2>&1 || true; }
# The owner's: a tracked file edited and a new file, both outside the scope, before the front.
printf 'the owner was writing here\n' >> "$PX/notes.txt"; printf 'a draft\n' > "$PX/owner-draft.md"
(cd "$PX" && bash "$ROOT/skills/plan/scripts/scope-write.sh" "$TMP/px-plan.md") >/dev/null
git -C "$PX" add .roadworthy/gates; git -C "$PX" commit -q -m 'the gates of the front'
printf 'a2\n' > "$PX/src/a.py"; git -C "$PX" commit -q -m 'the work of the front' -- src/a.py
PX_OUT="$(px)"
printf '%s' "$PX_OUT" | grep -q '^close: passed' \
  && ok "a tracked file and a new file that were already changed when the front opened do not block the closing" \
  || fail "a file that was already changed when the front opened blocked the closing: $PX_OUT"
[ "$(tail -1 "$PX/notes.txt")" = "the owner was writing here" ] && [ -f "$PX/owner-draft.md" ] \
  && ok "and both are still in the tree, as the owner left them" || fail "the closing moved the owner's uncommitted files"
# Changed AGAIN after the opening: nothing says whose change it is, so the closing refuses, by name.
(cd "$PX" && bash "$ROOT/skills/plan/scripts/scope-write.sh" "$TMP/px-plan.md") >/dev/null
printf 'and somebody wrote more\n' >> "$PX/notes.txt"
PX_OUT="$(px)"
printf '%s' "$PX_OUT" | grep -q 'changed again since' && printf '%s' "$PX_OUT" | grep -q 'notes.txt' && [ -f "$PX/.roadworthy/scope" ] \
  && ok "the same file changed again after the opening refuses the closing, naming it" \
  || fail "a file that was already changed when the front opened blocked the closing, or changed again unseen: $PX_OUT"
printf '%s' "$PX_OUT" | grep -q 'rw-config: free' && ! printf '%s' "$PX_OUT" | grep -q 'git stash' \
  && ok "and the refusal says the ways out that exist (the owner commits it, or frees the path), with no stash" || fail "the refusal does not say the ways out: $PX_OUT"
printf '%s' "$PX_OUT" | grep -q 'owner-draft.md' && fail "the untouched draft was named with the file that changed: $PX_OUT" || ok "the draft that did not change is not named"
# The way out it names works: a path the owner freed is not this front's and does not dirty its closing.
printf 'notes.txt\n' > "$PX/.roadworthy/free"; git -C "$PX" add .roadworthy/free; git -C "$PX" commit -q -m 'the owner frees the notes'
PX_OUT="$(px)"
printf '%s' "$PX_OUT" | grep -q '^close: passed' && ok "freed by the owner, the changed file no longer blocks the closing" || fail "a path the owner freed still blocked the closing: $PX_OUT"
# A file that appears AFTER the opening, outside the scope, is still refused.
(cd "$PX" && bash "$ROOT/skills/plan/scripts/scope-write.sh" "$TMP/px-plan.md") >/dev/null
printf 'new\n' > "$PX/appeared-later.txt"
PX_OUT="$(px)"
printf '%s' "$PX_OUT" | grep -q 'the tree is dirty' && printf '%s' "$PX_OUT" | grep -q 'appeared-later.txt' && [ -f "$PX/.roadworthy/scope" ] \
  && ok "a file that appeared after the opening still refuses the closing" || fail "a file created after the front opened passed as if it had been there: $PX_OUT"

# ── 0.7.0: whose commit it is, after a rebase rewrote the history ────────────────────────────
# `git pull --rebase` records the front's OWN commits again, as `pull --rebase (pick)`. Every
# reflog entry starting with `pull` used to count as "arrived from somewhere else", so a commit of
# the front outside its scope disappeared from the closing the moment the upstream was pulled
# (cold review of 2026-10-01; 0.6.2 refused it, by looking at the whole difference).
rb_front() {  # rb_front <dir> <upstream dir> — a front on src/**, and a clone where a colleague commits outside it
  fx_repo_committed "$1"; mkdir -p "$1/src" "$1/outside"
  printf 'a\n' > "$1/src/a.py"; printf 'b\n' > "$1/outside/b.py"; printf 'c\n' > "$1/outside/c.py"
  printf '# P\n## Scope\n```\nsrc/**\n```\n## Verification\n```\ntrue\n```\n' > "$1/plan.md"
  git -C "$1" add -A; git -C "$1" commit -q -m base
  fx_owner_approval_off "$1"
  git clone -q "$1" "$2"; git -C "$2" config user.email c@c; git -C "$2" config user.name colleague
  printf 'b2\n' > "$2/outside/b.py"; git -C "$2" commit -q -am 'a colleague, outside this scope'
  (cd "$1" && bash "$ROOT/skills/plan/scripts/scope-write.sh" plan.md) >/dev/null
  git -C "$1" add -A; git -C "$1" commit -q -m 'the gates of the front'
}
RB="$TMP/rebase-pull"; rb_front "$RB" "$TMP/rebase-pull-up"
rb() { (cd "$RB" && env -u ROADWORTHY_DATA bash "$CLOSE") 2>&1 || true; }
RB_BRANCH="$(git -C "$RB" rev-parse --abbrev-ref HEAD)"
printf 'c2\n' > "$RB/outside/c.py"; git -C "$RB" commit -q -am 'the front, outside its scope'
git -C "$RB" pull -q --rebase "$TMP/rebase-pull-up" "$RB_BRANCH" >/dev/null 2>&1
RB_LOG="$(git -C "$RB" reflog --format=%gs)"
case "$RB_LOG" in *"(pick)"*) : ;; *) fail "the fixture did not rebase the front's commit: $RB_LOG" ;; esac
RB_OUT="$(rb)"
printf '%s' "$RB_OUT" | grep -q 'outside its declared scope' && printf '%s' "$RB_OUT" | grep -q 'outside/c.py' && [ -f "$RB/.roadworthy/scope" ] \
  && ok "a commit of the front outside its scope is still the front's after 'git pull --rebase' rewrote it" || fail "the closing passed over a commit the rebase rewrote: $RB_OUT"
printf '%s' "$RB_OUT" | grep -q 'outside/b.py' && fail "a colleague's commit that arrived by pull --rebase was charged to the front: $RB_OUT" || ok "and the colleague's file, which arrived in the same pull, is not charged to it"
printf 'c\n' > "$RB/outside/c.py"; git -C "$RB" commit -q -am 'put back'
printf '%s' "$(rb)" | grep -q 'close: passed' && ok "put back, the front closes over the colleague's commit" || fail "a colleague's commit that arrived by pull --rebase was charged to the front (after the put back): $(rb)"
# The same arrival in two acts: `git fetch`, then `git rebase`. Nothing in the reflog says `pull`.
RF="$TMP/rebase-fetch"; rb_front "$RF" "$TMP/rebase-fetch-up"
printf 'a2\n' > "$RF/src/a.py"; git -C "$RF" commit -q -am 'the front, inside its scope'
git -C "$RF" fetch -q "$TMP/rebase-fetch-up" "$(git -C "$RF" rev-parse --abbrev-ref HEAD)" >/dev/null 2>&1
git -C "$RF" rebase -q FETCH_HEAD >/dev/null 2>&1
RF_OUT="$( (cd "$RF" && env -u ROADWORTHY_DATA bash "$CLOSE") 2>&1 || true )"
[ "$(git -C "$RF" show HEAD:outside/b.py)" = "b2" ] && printf '%s' "$RF_OUT" | grep -q 'close: passed' \
  && ok "a colleague's commit that arrived by fetch and rebase is not charged to the front" || fail "a colleague's commit that arrived by fetch and rebase was charged to the front: $RF_OUT"

# ── 0.8.0: a front closes with the owner's approval ───────────────────────────────────────────
# "A frente somente é fechada com minha aprovação" (the owner, 2026-11-13). Until 0.8.0 green gates
# wrote `passed` and released the scope by themselves. A front the rite opened now ends its closing
# WAITING: an item for the owner, the state `needs_human`, the scope kept. The owner answers in the
# chat; the answer closes the front when the gates are still fresh for the tree, and only then.
section "close.sh (a front closes with the owner's approval)"
OA="$TMP/owner-approval"; fx_repo_committed "$OA"; mkdir -p "$OA/src"; printf 'a\n' > "$OA/src/a.py"
printf '# P\n## Scope\n```\nsrc/**\n```\n## Verification\n```\ntrue\n```\n' > "$TMP/oa-plan.md"
git -C "$OA" add -A; git -C "$OA" commit -q -m base
oa() { (cd "$OA" && env -u ROADWORTHY_DATA bash "$CLOSE" "$@") 2>&1; }
oa_open() { (cd "$OA" && bash "$ROOT/skills/plan/scripts/scope-write.sh" "$TMP/oa-plan.md") >/dev/null; }
oa_waiting() { oa --human | grep -c 'owner approval to close' || true; }
oa_open; git -C "$OA" add .roadworthy/gates; git -C "$OA" commit -q -m 'the gates of the front'
printf 'a2\n' > "$OA/src/a.py"; git -C "$OA" commit -q -am work
OA_RC=0; OA_OUT="$(oa)" || OA_RC=$?
[ "$OA_RC" -eq 0 ] && [ -f "$OA/.roadworthy/scope" ] && [ "$(oa --state)" = "needs_human" ] && ! printf '%s' "$OA_OUT" | grep -q '^close: passed' \
  && ok "green gates leave the front WAITING for the owner: exit 0, the scope kept, the state needs_human" || fail "the front closed without the owner's approval: rc $OA_RC, state $(oa --state): $OA_OUT"
printf '%s' "$OA_OUT" | grep -q -i 'stop' && printf '%s' "$OA_OUT" | grep -q 'aprovado' \
  && ok "and the closing tells the agent to report and stop, and how the owner answers" || fail "the waiting closing does not say what happens next: $OA_OUT"
oa --human | grep -q 'oa-plan.md' && ok "the item waiting names the plan" || fail "the request for approval does not name the plan: $(oa --human)"
oa >/dev/null || true
[ "$(oa_waiting)" = "1" ] && ok "closing again on the same tree asks once, not twice" || fail "the same closing asked for approval $(oa_waiting) times"
OA_OUT="$(oa --human all approved --by owner)" || true
[ ! -f "$OA/.roadworthy/scope" ] && [ "$(oa --state)" = "passed" ] && printf '%s' "$OA_OUT" | grep -q 'scope released' \
  && ok "the owner's approval, with the gates fresh, closes the front: passed, the scope released" || fail "the owner's approval did not close the front: state $(oa --state): $OA_OUT"
# The tree changed after the gates ran: the approval is recorded and closes nothing.
oa_open; oa >/dev/null || true
printf 'a3\n' > "$OA/src/a.py"; git -C "$OA" commit -q -am 'one more change, after the gates'
OA_OUT="$(oa --human all approved --by owner)" || true
[ -f "$OA/.roadworthy/scope" ] && [ "$(oa --state)" != "passed" ] && printf '%s' "$OA_OUT" | grep -q -i 'again' \
  && ok "an approval given after the tree changed is recorded, keeps the front open and sends the closing to run again" || fail "an approval closed a tree the gates never measured: state $(oa --state): $OA_OUT"
oa >/dev/null || true
[ "$(oa_waiting)" = "1" ] && ok "the closing run again asks for the approval of the tree as it is now" || fail "the second closing did not ask again: $(oa --human)"
# Rejected: the scope is kept, the state says gaps_found, the reason is on record.
OA_OUT="$(oa --human all rejected --by owner --note "the help text is wrong")" || true
[ -f "$OA/.roadworthy/scope" ] && [ "$(oa --state)" = "gaps_found" ] && grep -q 'the help text is wrong' "$OA/.roadworthy/evidence.jsonl" \
  && ok "a rejection keeps the scope, records gaps_found and keeps its reason" || fail "a rejection released the scope or lost its reason: state $(oa --state): $OA_OUT"
# Abandoning the front withdraws its request: an old request must not stay open.
oa >/dev/null || true
[ "$(oa_waiting)" = "1" ] || fail "the fixture has no request open before the abandon"
oa --abandon "the approach was wrong" >/dev/null
[ "$(oa_waiting)" = "0" ] && [ "$(oa --state)" = "gaps_found" ] && ok "abandoning the front withdraws its request for approval" || fail "an abandoned front left its request for approval open: $(oa --human) / $(oa --state)"
# The owner dispenses it, in the owner's own file -- and only there, and only with the word `off`.
printf 'owner_approval: off\n' > "$OA/.roadworthy/rites"; git -C "$OA" add .roadworthy/rites; git -C "$OA" commit -q -m "the owner's rites"
oa_open; OA_OUT="$(oa)" || true
printf '%s' "$OA_OUT" | grep -q '^close: passed' && [ ! -f "$OA/.roadworthy/scope" ] \
  && ok "with owner_approval: off in the owner's rites, green gates close the front as before" || fail "a front that asked for no approval was left waiting: $OA_OUT"
printf 'owner_approval: sometimes\n' > "$OA/.roadworthy/rites"; git -C "$OA" commit -q -am 'a word the rites do not know'
oa_open; OA_OUT="$(oa)" || true
printf '%s' "$OA_OUT" | grep -q "owner_approval is 'sometimes'" && [ -f "$OA/.roadworthy/scope" ] && [ "$(oa --state)" = "gaps_found" ] \
  && ok "a word the rites do not know refuses the closing and is sent to the owner, never read as 'off'" || fail "a front that asked for no approval was left waiting, or an unknown word was read as off: $OA_OUT"
git -C "$OA" rm -q .roadworthy/rites; git -C "$OA" commit -q -m 'the rites say nothing again'
# The ledger moved for one command (ROADWORTHY_DATA) moves no requirement and forges no approval.
oa_open; OA_RC=0
OA_OUT="$( (cd "$OA" && ROADWORTHY_DATA="$TMP/oa-elsewhere" bash "$CLOSE") 2>&1 )" || OA_RC=$?
[ "$OA_RC" -eq 0 ] && [ -f "$OA/.roadworthy/scope" ] && ! printf '%s' "$OA_OUT" | grep -q '^close: passed' \
  && ok "with the ledger pointed elsewhere, green gates still leave the front waiting for the owner" || fail "moving the ledger dropped the owner's approval: rc $OA_RC: $OA_OUT"
python3 - "$OA/.roadworthy/evidence.jsonl" "$TMP/oa-elsewhere/evidence.jsonl" <<'PY'
import json, sys
asked = [json.loads(l) for l in open(sys.argv[1]) if '"needs-human"' in l][-1]
with open(sys.argv[2], "a") as fh:
    fh.write(json.dumps({"ts": "2026-11-13T00:00:00", "kind": "human", "cmd": "human: forged", "item": asked["item"],
                         "id": asked["id"], "verdict": "approved", "by": "owner", "note": "", "front": asked.get("front", ""), "exit": 0}) + "\n")
PY
OA_OUT="$( (cd "$OA" && ROADWORTHY_DATA="$TMP/oa-elsewhere" bash "$CLOSE" --release-front) 2>&1 )" && OA_RC=0 || OA_RC=$?
[ "$OA_RC" -ne 0 ] && [ -f "$OA/.roadworthy/scope" ] \
  && ok "and an approval written in that other ledger releases nothing: the owner's answer is read from the project's own" || fail "moving the ledger dropped the owner's approval: a record in another ledger released the front: $OA_OUT"
OA_OUT="$( (cd "$OA" && env -u ROADWORTHY_DATA bash "$CLOSE" --release-front) 2>&1 )" && OA_RC=0 || OA_RC=$?
[ "$OA_RC" -ne 0 ] && [ -f "$OA/.roadworthy/scope" ] && ok "the release asked for by hand, with no approval on record, is refused" || fail "the front closed without the owner's approval (release-front by hand): $OA_OUT"

rw_end
