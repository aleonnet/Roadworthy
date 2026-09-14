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
bash skills/plan/scripts/scope-write.sh "$SWB/p.md" --root "$SWB" --base "$SWB_FIRST" >/dev/null 2>&1
[ "$(python3 -c 'import json;print(json.load(open("'"$SWB"'/.roadworthy/plan.snapshot"))["base_head"])')" = "$SWB_FIRST" ] \
  && ok "--base keeps the front's real base when it is reopened" || fail "--base ignored"
bash skills/plan/scripts/scope-write.sh "$SWB/p.md" --root "$SWB" --base no-such-ref >"$TMP/swb.out" 2>&1 \
  && fail "a base that does not resolve was accepted" \
  || { grep -q "does not resolve" "$TMP/swb.out" && ok "a base that does not resolve refuses to open the front" || fail "wrong refusal: $(cat "$TMP/swb.out")"; }

rw_end
