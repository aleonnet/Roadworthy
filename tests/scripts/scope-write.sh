#!/usr/bin/env bash
# scope-write
# Run alone: bash tests/scripts/scope-write.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── scope-write + the closing measured against the snapshot ─────────────────
section "scope-write.sh / plan.snapshot"
SW="$TMP/sw"; SWD="$TMP/swdata"; mkdir -p "$SW/src" "$SWD"
git -C "$SW" init -q; git -C "$SW" config user.email t@t; git -C "$SW" config user.name t
echo base > "$SW/src/a.txt"
printf '# P\n## Escopo\n```\nsrc/**\nplan.md\n```\n## Verificação\n```\ntrue\n```\n' > "$SW/plan.md"
git -C "$SW" add -A; git -C "$SW" commit -q -m base
(cd "$SW" && bash "$ROOT/skills/plan/scripts/scope-write.sh" plan.md) >/dev/null \
  && ok "scope-write opens a front from the plan" || fail "scope-write failed"
[ -f "$SW/.roadworthy/scope" ] && [ -f "$SW/.roadworthy/gates" ] && [ -f "$SW/.roadworthy/plan.snapshot" ] \
  && ok "it writes the scope, the gates and the snapshot in one act" || fail "scope-write wrote only some of the three"
python3 -c 'import json,sys
s=json.load(open(sys.argv[1]))
need={"ts","plan","plan_name","base_head","scope_globs","gates","digests"}
sys.exit(0 if not (need-set(s)) and set(s["digests"])=={"scope","gates","snapshot_canonical"} else 1)' "$SW/.roadworthy/plan.snapshot" \
  && ok "the snapshot carries the plan, the base HEAD, the globs, the gates and three digests" || fail "snapshot shape"
# Both sections are read as FENCED BLOCKS. A prose bullet is not a command, and close.sh runs each
# gate line with bash -c: accepting bullets would put `- \`cmd\` → expected result` into the gates file.
printf '# P\n## Escopo\n```\nsrc/**\n```\n## Verificação\n- `true` → green\n' > "$TMP/prose.md"
! (cd "$SW" && bash "$ROOT/skills/plan/scripts/scope-write.sh" "$TMP/prose.md" --root "$SW") >/dev/null 2>&1 \
  && ok "a Verification written as prose bullets is refused" || fail "prose accepted as gates"
printf '# P\n## Escopo\n```\n```\n## Verificação\n```\ntrue\n```\n' > "$TMP/empty.md"
! (cd "$SW" && bash "$ROOT/skills/plan/scripts/scope-write.sh" "$TMP/empty.md" --root "$SW") >/dev/null 2>&1 \
  && ok "an empty Scope block is refused: a front with no scope is not a front" || fail "empty scope accepted"
git -C "$SW" add -A; git -C "$SW" commit -q -m 'front open'
# An honest front closes.
echo changed > "$SW/src/a.txt"; git -C "$SW" commit -qam 'inside the scope'
SWOK="$( (cd "$SW" && ROADWORTHY_DATA="$SWD" bash "$ROOT/skills/close/scripts/close.sh") 2>&1 || true )"
printf '%s' "$SWOK" | grep -q '^close: passed' \
  && ok "a front that stayed inside its globs closes" || fail "honest front refused: $SWOK"
# The foundation cannot be edited after approval.
SW2="$TMP/sw2"; SWD2="$TMP/swdata2"; mkdir -p "$SW2/src" "$SWD2"
git -C "$SW2" init -q; git -C "$SW2" config user.email t@t; git -C "$SW2" config user.name t
echo base > "$SW2/src/a.txt"
printf '# P\n## Escopo\n```\nsrc/**\nplan.md\n```\n## Verificação\n```\ntrue\n```\n' > "$SW2/plan.md"
git -C "$SW2" add -A; git -C "$SW2" commit -q -m base
(cd "$SW2" && bash "$ROOT/skills/plan/scripts/scope-write.sh" plan.md) >/dev/null
printf 'false\n' >> "$SW2/.roadworthy/gates"
git -C "$SW2" add -A; git -C "$SW2" commit -q -m 'gates edited by hand'
SWERR="$( (cd "$SW2" && ROADWORTHY_DATA="$SWD2" bash "$ROOT/skills/close/scripts/close.sh") 2>&1 || true )"
printf '%s' "$SWERR" | grep -q 'changed since the front opened' \
  && ok "editing the gates after approval is refused, with both digests named" || fail "hand-edited gates accepted: $SWERR"
# A file touched outside the declared globs surfaces at the closing, even when it was written
# through the shell and the lock never saw it.
SW3="$TMP/sw3"; SWD3="$TMP/swdata3"; mkdir -p "$SW3/src" "$SWD3"
git -C "$SW3" init -q; git -C "$SW3" config user.email t@t; git -C "$SW3" config user.name t
echo base > "$SW3/src/a.txt"
printf '# P\n## Escopo\n```\nsrc/**\nplan.md\n```\n## Verificação\n```\ntrue\n```\n' > "$SW3/plan.md"
git -C "$SW3" add -A; git -C "$SW3" commit -q -m base
(cd "$SW3" && bash "$ROOT/skills/plan/scripts/scope-write.sh" plan.md) >/dev/null
git -C "$SW3" add -A; git -C "$SW3" commit -q -m 'front open'
echo stray > "$SW3/outside.txt"; git -C "$SW3" add -A; git -C "$SW3" commit -q -m 'outside the scope'
SWERR3="$( (cd "$SW3" && ROADWORTHY_DATA="$SWD3" bash "$ROOT/skills/close/scripts/close.sh") 2>&1 || true )"
printf '%s' "$SWERR3" | grep -q 'outside its declared scope' && printf '%s' "$SWERR3" | grep -q 'outside.txt' \
  && ok "a file touched outside the globs refuses the closing, and is named" || fail "stray file closed the front: $SWERR3"
# The plugin's own bookkeeping is not the front's subject: .roadworthy/ never counts as stray.
printf '%s' "$SWERR3" | grep -q '\.roadworthy/' && fail "the closing counted its own bookkeeping as stray" \
  || ok "the plugin's own .roadworthy/ files are not counted against the front"

# ── goldens: the envelope every guard returns, compared key for key ─────────
# Reopening a front mid-flight must not silently reset what the closing measures against.
SWB="$TMP/swbase"; mkdir -p "$SWB"
git -C "$SWB" init -q; git -C "$SWB" config user.email t@t; git -C "$SWB" config user.name t
printf 'a\n' > "$SWB/f.txt"; git -C "$SWB" add -A; git -C "$SWB" -c commit.gpgsign=false commit -qm one
SWB_FIRST="$(git -C "$SWB" rev-parse HEAD)"
printf 'b\n' > "$SWB/f.txt"; git -C "$SWB" add -A; git -C "$SWB" -c commit.gpgsign=false commit -qm two
cat > "$SWB/p.md" <<'SWBP'
# p
## Scope
```
f.txt
```
## Verification
```
true
```
SWBP
bash skills/plan/scripts/scope-write.sh "$SWB/p.md" --root "$SWB" >/dev/null 2>&1
[ "$(python3 -c 'import json;print(json.load(open("'"$SWB"'/.roadworthy/plan.snapshot"))["base_head"])')" = "$(git -C "$SWB" rev-parse HEAD)" ] \
  && ok "with no --base the front opens on HEAD, as it always did" || fail "the default base changed"
swb_base() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["base_head"])' "$SWB/.roadworthy/plan.snapshot"; }
SWB_OPEN="$(swb_base)"
# 0.7.0: the SAME front reopened keeps the base it opened with, by itself. Until then that
# depended on whoever reopened remembering --base, and forgetting it moved what the closing
# measures (field note, 2026-09-18).
printf 'c\n' > "$SWB/f.txt"; git -C "$SWB" add -A; git -C "$SWB" -c commit.gpgsign=false commit -qm three
bash skills/plan/scripts/scope-write.sh "$SWB/p.md" --root "$SWB" >"$TMP/swb.out" 2>&1
[ "$(swb_base)" = "$SWB_OPEN" ] && grep -q 'reopened' "$TMP/swb.out" \
  && ok "the same front reopened keeps its base, with no --base given" || fail "reopening moved the base: $(swb_base) is not $SWB_OPEN"
bash skills/plan/scripts/scope-write.sh "$SWB/p.md" --root "$SWB" --base "$SWB_FIRST" >"$TMP/swb.out" 2>&1 \
  && fail "reopening moved the base: a different --base was accepted" \
  || { grep -q 'Reopening keeps the base' "$TMP/swb.out" && [ "$(swb_base)" = "$SWB_OPEN" ] \
       && ok "and a --base that disagrees with it is refused" || fail "reopening moved the base (wrong refusal): $(cat "$TMP/swb.out")"; }
bash skills/plan/scripts/scope-write.sh "$SWB/p.md" --root "$SWB" --base "$SWB_OPEN" >/dev/null 2>&1 \
  && ok "the same base said out loud is accepted" || fail "reopening with its own base was refused"
# One front at a time: another plan over a live scope is refused, naming the live one.
sed 's/^# p$/# q/' "$SWB/p.md" > "$SWB/q.md"
bash skills/plan/scripts/scope-write.sh "$SWB/q.md" --root "$SWB" >"$TMP/swb.out" 2>&1 \
  && fail "a second front opened over a live one" \
  || { grep -q 'p.md' "$TMP/swb.out" && grep -q -- '--abandon' "$TMP/swb.out" \
       && ok "a second front over a live one is refused, naming it and the two ways out" || fail "a second front opened over a live one (wrong refusal): $(cat "$TMP/swb.out")"; }
# ...and both ways out work: abandoned, the next front opens, on the tip.
(cd "$SWB" && bash "$ROOT/skills/close/scripts/close.sh" --abandon "replanned") >/dev/null 2>&1
bash skills/plan/scripts/scope-write.sh "$SWB/q.md" --root "$SWB" >/dev/null 2>&1 && [ "$(swb_base)" = "$(git -C "$SWB" rev-parse HEAD)" ] \
  && ok "after the live front is abandoned, the next one opens, on the tip" || fail "abandoning did not free the next front (a dead end)"
(cd "$SWB" && bash "$ROOT/skills/close/scripts/close.sh" --abandon "test") >/dev/null 2>&1
# A fresh front may still name its base, and a base that does not resolve refuses.
bash skills/plan/scripts/scope-write.sh "$SWB/p.md" --root "$SWB" --base "$SWB_FIRST" >/dev/null 2>&1 && [ "$(swb_base)" = "$SWB_FIRST" ] \
  && ok "a new front may name its base with --base" || fail "--base ignored on a new front"
(cd "$SWB" && bash "$ROOT/skills/close/scripts/close.sh" --abandon "test") >/dev/null 2>&1
bash skills/plan/scripts/scope-write.sh "$SWB/p.md" --root "$SWB" --base no-such-ref >"$TMP/swb.out" 2>&1 \
  && fail "a base that does not resolve was accepted" \
  || { grep -q "does not resolve" "$TMP/swb.out" && ok "a base that does not resolve refuses to open the front" || fail "wrong refusal: $(cat "$TMP/swb.out")"; }
# What the snapshot carries from 0.7.0: the fingerprint of what was approved, the reporting form
# the plan agreed, and what was already changed outside the scope when the front opened.
printf 'x\n' > "$SWB/loose.txt"
sed 's/^# p$/# p\nreport: prose, the conclusion first\n/' "$SWB/p.md" > "$SWB/r.md"
bash skills/plan/scripts/scope-write.sh "$SWB/r.md" --root "$SWB" >/dev/null 2>&1
python3 - "$SWB/.roadworthy/plan.snapshot" "$(python3 hooks/planblocks.py fingerprint "$SWB/r.md")" <<'PY' \
  && ok "the snapshot carries the plan's fingerprint, its reporting form and what was already changed outside the scope" || fail "the agreed reporting form did not reach the snapshot (or the fingerprint, or the pre-existing changes)"
import json, sys
s = json.load(open(sys.argv[1]))
assert s["fingerprint"] == sys.argv[2] and len(s["fingerprint"]) == 64, "fingerprint"
assert s["report"] == "prose, the conclusion first", "report: %r" % s.get("report")
assert "loose.txt" in s["preexisting"], "preexisting: %r" % s.get("preexisting")
PY

# ── 0.8.0: the standing gates of the project ────────────────────────────────────────────────
# What a project asks of EVERY closing lived in the newest plan under docs/plans/done, to be copied
# by hand into the next one ("it is this repository's quality bar", the runbook said). Forgotten,
# the front closed without it. `.roadworthy/standing-gates` is the owner's file: one command per
# line, joined to the gates of every front when it opens -- and kept apart in the snapshot, so the
# fingerprint of the plan (what the approval approved) is still the plan's.
section "scope-write.sh (the standing gates of the project)"
SG="$TMP/standing"; fx_repo_committed "$SG"; mkdir -p "$SG/src" "$SG/.roadworthy"; printf 'a\n' > "$SG/src/a.txt"
printf '# what every closing of this project runs\ntest -f src/a.txt\n\ntrue\n' > "$SG/.roadworthy/standing-gates"
printf '# P\n## Scope\n```\nsrc/**\n```\n## Verification\n```\ntrue\n```\n' > "$TMP/sg-plan.md"
git -C "$SG" add -A; git -C "$SG" commit -q -m base
SG_OPEN="$( (cd "$SG" && bash "$ROOT/skills/plan/scripts/scope-write.sh" "$TMP/sg-plan.md") 2>&1 )"
git -C "$SG" add .roadworthy/gates; git -C "$SG" commit -q -m 'the gates of the front'
sg_lines() { grep -v -E '^[[:space:]]*(#|$)' "$SG/.roadworthy/gates"; }
[ "$(sg_lines)" = "$(printf 'true\ntest -f src/a.txt')" ] \
  && ok "the standing gates are joined to the gates of the front, after the plan's, and one already in the plan is not repeated" \
  || fail "a standing gate did not run at the closing: it is not in the gates of the front: $(sg_lines | tr '\n' '|')"
printf '%s' "$SG_OPEN" | grep -q 'standing' && ok "and the opening says how many it added" || fail "the opening is silent about the standing gates: $SG_OPEN"
python3 - "$SG/.roadworthy/plan.snapshot" "$(python3 hooks/planblocks.py fingerprint "$TMP/sg-plan.md")" <<'PY' \
  && ok "the snapshot keeps them apart, and the fingerprint is still the plan's" || fail "the standing gates changed the fingerprint of the plan, or are not in the snapshot"
import json, sys
s = json.load(open(sys.argv[1]))
assert s["fingerprint"] == sys.argv[2], "fingerprint"
assert s["gates"] == ["true"], "gates: %r" % s["gates"]
assert s["standing_gates"] == ["test -f src/a.txt"], "standing: %r" % s.get("standing_gates")
PY
SG_FACTS="$(python3 hooks/frontcheck.py "$SG" "$SG/.roadworthy/evidence.jsonl" false)"
[ -z "$SG_FACTS" ] && ok "and the fence that measures the front finds it intact" || fail "a front with standing gates is called broken: $SG_FACTS"
SG_OUT="$( (cd "$SG" && env -u ROADWORTHY_DATA bash "$ROOT/skills/close/scripts/close.sh") 2>&1 || true )"
printf '%s' "$SG_OUT" | grep -q 'OK    test -f src/a.txt' && printf '%s' "$SG_OUT" | grep -q '^close: passed' \
  && ok "the closing runs the standing gate with the plan's" || fail "a standing gate did not run at the closing: $SG_OUT"
# A standing gate that fails keeps the front open, like any gate.
printf 'test -f src/not-there.txt\n' > "$SG/.roadworthy/standing-gates"; git -C "$SG" add -A; git -C "$SG" commit -q -m 'the owner asks for more'
(cd "$SG" && bash "$ROOT/skills/plan/scripts/scope-write.sh" "$TMP/sg-plan.md") >/dev/null 2>&1
git -C "$SG" add .roadworthy/gates; git -C "$SG" commit -q --allow-empty -m 'the gates of the front'
SG_OUT="$( (cd "$SG" && env -u ROADWORTHY_DATA bash "$ROOT/skills/close/scripts/close.sh") 2>&1 || true )"
printf '%s' "$SG_OUT" | grep -q 'FAIL  test -f src/not-there.txt' && [ -f "$SG/.roadworthy/scope" ] \
  && ok "and a standing gate that fails keeps the front open" || fail "a standing gate did not run at the closing (a red one passed): $SG_OUT"

# ── 0.8.0: a plan that cites several repositories opens a front in each, in one act ─────────
# The fences judge a file by the repository IT is in. A plan whose Scope named files of two
# repositories opened one front, in the repository the script ran in; the lines about the other
# were enforced by nobody, and the files they name were denied for want of a front (27 refusals
# measured in the field between 2026-10-02 and 2026-11-13). Three repositories here: the plan's,
# one nested in it that keeps a rite of its own (a monorepo's subproject), and one elsewhere,
# cited by its absolute path.
section "scope-write.sh (a plan that cites several repositories)"
MA="$TMP/multi-a"; fx_repo "$MA"; MA="$(cd "$MA" && pwd -P)"; mkdir -p "$MA/src"; printf 'a\n' > "$MA/src/a.txt"; printf 'sub/\n' > "$MA/.gitignore"
git -C "$MA" add -A; git -C "$MA" commit -q -m base
MS="$MA/sub"; fx_repo "$MS"; mkdir -p "$MS/.roadworthy" "$MS/app"; printf 's\n' > "$MS/app/s.txt"; git -C "$MS" add -A; git -C "$MS" commit -q -m base
MB="$TMP/multi-b"; fx_repo "$MB"; MB="$(cd "$MB" && pwd -P)"; mkdir -p "$MB/lib"; printf 'b\n' > "$MB/lib/b.txt"; git -C "$MB" add -A; git -C "$MB" commit -q -m base
mplan() {  # mplan <file> <gate lines...> — the Scope cites the three repositories
  local f="$1"; shift
  { printf '# P\n## Scope\n```\nsrc/**\nsub/app/**\n%s/lib/**\n```\n## Verification\n```\n' "$MB"; printf '%s\n' "$@"; printf '```\n'; } > "$f"
}
SWS="$ROOT/skills/plan/scripts/scope-write.sh"; MCLOSE="$ROOT/skills/close/scripts/close.sh"
lines() { grep -v -E '^[[:space:]]*(#|$)' "$1" 2>/dev/null | tr '\n' '|'; }
# A repository the Scope cites and no gate measures: refused whole, nothing written anywhere.
mplan "$TMP/multi-nogate.md" 'true' 'cd sub && test -f app/s.txt'
M_OUT="$( (cd "$MA" && bash "$SWS" "$TMP/multi-nogate.md") 2>&1 )" && fail "a repository cited with no gate of its own opened a front: $M_OUT" \
  || { printf '%s' "$M_OUT" | grep -q "$MB" && [ ! -f "$MA/.roadworthy/scope" ] && [ ! -f "$MS/.roadworthy/scope" ] && [ ! -f "$MB/.roadworthy/scope" ] \
       && ok "a cited repository that would be left with no gate is refused by name, and nothing is written in any of them" || fail "a repository cited with no gate: wrong refusal, or a front half open: $M_OUT"; }
mplan "$TMP/multi.md" 'true' 'cd sub && test -f app/s.txt' "cd $MB && test -f lib/b.txt"
# A live front of ANOTHER plan in one of them: refused whole, too.
fx_front_rite "$MB" 'lib/**' 'true'
M_OUT="$( (cd "$MA" && bash "$SWS" "$TMP/multi.md") 2>&1 )" && fail "a front opened over the live front of another plan in a second repository: $M_OUT" \
  || { printf '%s' "$M_OUT" | grep -q "$MB" && printf '%s' "$M_OUT" | grep -q -- '--abandon' && [ ! -f "$MA/.roadworthy/scope" ] \
       && ok "a live front of another plan in one of the repositories refuses the whole opening, naming where" || fail "a live front elsewhere: wrong refusal, or a front half open: $M_OUT"; }
(cd "$MB" && bash "$MCLOSE" --abandon "the test moves on") >/dev/null 2>&1
M_OUT="$( (cd "$MA" && bash "$SWS" "$TMP/multi.md") 2>&1 )" || fail "a plan citing three repositories could not open: $M_OUT"
[ "$(lines "$MA/.roadworthy/scope")" = 'src/**|' ] && [ "$(lines "$MS/.roadworthy/scope")" = 'app/**|' ] && [ "$(lines "$MB/.roadworthy/scope")" = 'lib/**|' ] \
  && ok "one act opens a front in each repository the Scope cites, each with its own lines, relative to it" \
  || fail "a plan citing two repositories opened only one front: $(lines "$MA/.roadworthy/scope") / $(lines "$MS/.roadworthy/scope") / $(lines "$MB/.roadworthy/scope")"
[ "$(lines "$MA/.roadworthy/gates")" = 'true|' ] && [ "$(lines "$MS/.roadworthy/gates")" = 'cd sub && test -f app/s.txt|' ] && [ "$(lines "$MB/.roadworthy/gates")" = "cd $MB && test -f lib/b.txt|" ] \
  && ok "and each gets the gates that are its own: the one that starts with cd into it" \
  || fail "a plan citing two repositories opened only one front (the gates were not divided): $(lines "$MA/.roadworthy/gates") / $(lines "$MS/.roadworthy/gates") / $(lines "$MB/.roadworthy/gates")"
python3 - "$(python3 hooks/planblocks.py fingerprint "$TMP/multi.md")" "$MA" "$MS" "$MB" <<'PY' \
  && ok "every snapshot carries the plan's fingerprint, the whole lists it comes from, the plan's repository and the repositories of the front" || fail "a plan citing two repositories opened only one front (the snapshots do not describe the whole front)"
import json, os, sys
fp, roots = sys.argv[1], sys.argv[2:]
for r in roots:
    s = json.load(open(os.path.join(r, ".roadworthy", "plan.snapshot")))
    assert s["fingerprint"] == fp, "fingerprint in %s" % r
    assert s["plan_root"] == roots[0], "plan_root in %s: %r" % (r, s.get("plan_root"))
    assert s["front_roots"] == roots, "front_roots in %s: %r" % (r, s.get("front_roots"))
    assert len(s["plan_scope"]) == 3 and len(s["plan_gates"]) == 3, "whole lists in %s" % r
PY
for r in "$MA" "$MS" "$MB"; do
  [ -z "$(python3 hooks/frontcheck.py "$r" "$r/.roadworthy/evidence.jsonl" false)" ] || fail "a front opened in a second repository was not honoured: frontcheck calls ${r##*/} broken: $(python3 hooks/frontcheck.py "$r" "$r/.roadworthy/evidence.jsonl" false)"
done
ok "the fence that measures a front finds each of the three intact"
# The part a repository enforces has to be ITS part of the approved plan. Forged whole -- the scope
# file, the snapshot's local list and every digest recomputed, the plan's own lists untouched --
# the fingerprint still matches the approval; what gives it away is deriving the part again.
cp "$MB/.roadworthy/scope" "$TMP/mb-scope.bak"; cp "$MB/.roadworthy/plan.snapshot" "$TMP/mb-snap.bak"
python3 - "$MB/.roadworthy" <<'PY'
import hashlib, json, os, sys
rw = sys.argv[1]
snap = json.load(open(os.path.join(rw, "plan.snapshot")))
snap.pop("digests")
snap["scope_globs"] = snap["scope_globs"] + ["**"]
first = open(os.path.join(rw, "scope")).read()
open(os.path.join(rw, "scope"), "w").write(first + "**\n")
sha = lambda p: hashlib.sha256(open(p, "rb").read()).hexdigest()
canonical = json.dumps(snap, sort_keys=True, separators=(",", ":"))
snap["digests"] = {"scope": sha(os.path.join(rw, "scope")), "gates": sha(os.path.join(rw, "gates")),
                   "snapshot_canonical": hashlib.sha256(canonical.encode()).hexdigest()}
json.dump(snap, open(os.path.join(rw, "plan.snapshot"), "w"), indent=1)
PY
M_FACTS="$(python3 hooks/frontcheck.py "$MB" "$MB/.roadworthy/evidence.jsonl" false)"
printf '%s' "$M_FACTS" | grep -q 'BROKEN.*not its part of the plan' \
  && ok "a local scope widened under an untouched plan, digests and all, is not the front that was approved" || fail "a wider local scope under an untouched plan kept the approval: $M_FACTS"
cp "$TMP/mb-scope.bak" "$MB/.roadworthy/scope"; cp "$TMP/mb-snap.bak" "$MB/.roadworthy/plan.snapshot"
[ -z "$(python3 hooks/frontcheck.py "$MB" "$MB/.roadworthy/evidence.jsonl" false)" ] && ok "put back, it is intact again" || fail "the fixture did not restore the front"
# The closing. The gates of a member run from the plan's repository, where the `cd` was written.
for r in "$MA" "$MS" "$MB"; do git -C "$r" add .roadworthy/gates; git -C "$r" commit -q -m 'the gates of the front'; done
printf 'a2\n' > "$MA/src/a.txt"; git -C "$MA" commit -q -am work
printf 's2\n' > "$MS/app/s.txt"; git -C "$MS" commit -q -am work
git -C "$MB" mv lib/b.txt lib/c.txt; git -C "$MB" commit -q -m 'inside the scope, and the gate of this repository goes red'
mclose() { (cd "$1" && env -u ROADWORTHY_DATA bash "$MCLOSE") 2>&1 || true; }
M_OUT="$(mclose "$MA")"
printf '%s' "$M_OUT" | grep -q '^close: passed' && fail "the front closed with a repository of it red: $M_OUT" \
  || { [ -f "$MA/.roadworthy/scope" ] && [ -f "$MS/.roadworthy/scope" ] && [ -f "$MB/.roadworthy/scope" ] && printf '%s' "$M_OUT" | grep -q "$MB" \
       && ok "a red gate in one repository of the front keeps the whole front open, and the closing names the repository" || fail "a red repository of the front: a scope was released, or the repository is not named: $M_OUT"; }
git -C "$MB" mv lib/c.txt lib/b.txt; git -C "$MB" commit -q -m 'put back'
M_OUT="$(mclose "$MB")"
printf '%s' "$M_OUT" | grep -q "$MA" && [ -f "$MB/.roadworthy/scope" ] && ! printf '%s' "$M_OUT" | grep -q '^close: passed' \
  && ok "run in another repository of the front, the closing measures that one and says where the front closes from" || fail "a member repository closed a part of the front by itself: $M_OUT"
M_OUT="$(mclose "$MA")"
printf '%s' "$M_OUT" | grep -q '^close: passed' && [ ! -f "$MA/.roadworthy/scope" ] && [ ! -f "$MS/.roadworthy/scope" ] && [ ! -f "$MB/.roadworthy/scope" ] \
  && [ "$(cat "$MA/.roadworthy/state")$(cat "$MS/.roadworthy/state")$(cat "$MB/.roadworthy/state")" = "passedpassedpassed" ] \
  && ok "run in the plan's repository with every one green, it closes the front in all of them" || fail "a green front in three repositories did not close in all of them: $M_OUT"
# The session entered the subproject, and the plan declares the repository that holds it: run
# there with no --root, the front opens from the plan's repository, not from the subproject.
{ printf '# P\n\nproject: %s\n\n' "$MA"; sed 1d "$TMP/multi.md"; } > "$TMP/multi-declared.md"
M_OUT="$( (cd "$MS" && bash "$SWS" "$TMP/multi-declared.md") 2>&1 )" || true
[ "$(lines "$MA/.roadworthy/scope")" = 'src/**|' ] && [ "$(lines "$MS/.roadworthy/scope")" = 'app/**|' ] \
  && ok "run inside a subproject, with a plan that declares the repository holding it, the front opens from the plan's repository" \
  || fail "a front opened from the subproject the session stood in, with the plan's lines read against the wrong repository: $M_OUT / $(lines "$MS/.roadworthy/scope")"
# And a front is abandoned whole, from the plan's repository.
(cd "$MA" && env -u ROADWORTHY_DATA bash "$MCLOSE" --abandon "the test ends here") >/dev/null 2>&1
[ ! -f "$MA/.roadworthy/scope" ] && [ ! -f "$MS/.roadworthy/scope" ] && [ ! -f "$MB/.roadworthy/scope" ] \
  && ok "abandoned from the plan's repository, the front is abandoned in every repository of it" || fail "an abandoned front was left open in a repository of it"

rw_end
