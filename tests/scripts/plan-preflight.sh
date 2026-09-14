#!/usr/bin/env bash
# plan-preflight
# Run alone: bash tests/scripts/plan-preflight.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── plan pre-flight ──────────────────────────────────────────────────────────
# The gate that replaced the reviewer's attention on things a machine can check. Every assertion
# here is one of those things, in both directions: it must reject the plan that lies and accept
# the plan that does not.
section "plan-preflight (the plan checked mechanically)"
PF="$TMP/pf"; mkdir -p "$PF"
(
  cd "$PF"
  git init -q .; git config user.email t@t; git config user.name t
  printf 'alpha line one\nalpha line two\nalpha line three\n' > a.txt
  printf 'beta line one\nbeta line two\n' > b.txt
  git add -A; git commit -qm base
) >/dev/null 2>&1
PF_HEAD="$(git -C "$PF" rev-parse HEAD)"

# plan_write <file> [extra section text...] — the plan that passes, as the baseline every
# variant below breaks in exactly one place.
plan_write() {
  cat > "$1" <<'PLAN'
# A plan

project: /tmp/pf

## Context

a.txt:2 — `alpha line two`

## Impact sweep

```
git -C . status --porcelain
```

## Scope

```
a.txt
b.txt
c-new.txt
```

**New files declared:** `c-new.txt`.

## Acceptance

| # | WHEN | THE SYSTEM SHALL |
|---|---|---|
| 1 | a | b |
| 2 | c | d |

## Declared corrections

| defect | path | old | new |
|---|---|---|---|
| 1 | `b.txt` | `beta line two` | gone |
PLAN
}
# tr_write <file> <command lines...> — a transcript in the harness's own shape.
tr_write() {
  local out="$1"; shift
  : > "$out"
  for c in "$@"; do
    python3 -c 'import json,sys; print(json.dumps({"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":sys.argv[1]}}]}}))' "$c" >> "$out"
  done
}
# pf <plan> <transcript> [args...] → OUT/RC of a pre-flight run
pf() {
  local p="$1" t="$2"; shift 2
  set +e
  OUT="$(cd "$PF" && bash "$ROOT/skills/plan/scripts/plan-preflight.sh" "$p" --root "$PF" ${t:+--transcript "$t"} "$@" 2>"$TMP/pf.err")"
  RC=$?
  set -e
  ERR="$(cat "$TMP/pf.err")"
}

plan_write "$PF/plan.md"
tr_write "$PF/t.jsonl" 'cat a.txt' 'echo hi
cat b.txt' 'git -C . status --porcelain'
pf "$PF/plan.md" "$PF/t.jsonl"
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'green' \
  && ok "a plan that proves what it claims passes" || fail "green plan rejected: $OUT $ERR"
printf '%s' "$OUT" | grep -q 'files proved read whole 2' \
  && ok "both scope files counted as read whole" || fail "reading count wrong: $OUT"
[ -s "$PF/.roadworthy/preflight.jsonl" ] \
  && ok "the run is recorded in preflight.jsonl" || fail "nothing recorded"

# A newline separates commands exactly as `;` does. Until this was fixed the reading inside a
# multi-line command was invisible and a file read whole counted as never read.
tr_write "$PF/t-nl.jsonl" 'cat a.txt' 'git -C . status --porcelain'
pf "$PF/plan.md" "$PF/t-nl.jsonl"
printf '%s' "$OUT" | grep -q 'b.txt was never read WHOLE' \
  && ok "a file absent from the transcript is named" || fail "unread file not named: $OUT"

# `head -N` is a WINDOW. It used to count here, which is the instrument accepting the very thing
# it exists to refuse.
tr_write "$PF/t-head.jsonl" 'cat a.txt' 'head -20 b.txt' 'git -C . status --porcelain'
pf "$PF/plan.md" "$PF/t-head.jsonl"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'b.txt was never read WHOLE' \
  && ok "head -N does not count as a whole reading" || fail "a window passed as a reading: $OUT"

# Citations are checked by CONTENT. Checking that the line merely exists is what let a false
# citation be signed.
sed 's/alpha line two/alpha line WRONG/' "$PF/plan.md" > "$PF/plan-cit.md"
pf "$PF/plan-cit.md" "$PF/t.jsonl"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'citation a.txt:2 does not match the line' \
  && ok "a citation the line does not sustain is rejected" || fail "false citation passed: $OUT"

# And they are read against the BASE, not against the tree: a correction made during the front
# must not turn the plan's own citation into a false alarm.
printf 'alpha CHANGED\nalpha line two\nalpha line three\n' > "$PF/a.txt"
sed 's/alpha line two`/alpha CHANGED`/; s/a.txt:2/a.txt:1/' "$PF/plan.md" > "$PF/plan-base.md"
pf "$PF/plan-base.md" "$PF/t.jsonl"
[ "$RC" -eq 0 ] && ok "a citation of the tree passes against the tree" || fail "tree citation failed: $OUT"
pf "$PF/plan-base.md" "$PF/t.jsonl" --base "$PF_HEAD"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'citation a.txt:1 does not match' \
  && ok "with a base, the base decides, not the tree" || fail "the base was ignored: $OUT"
pf "$PF/plan.md" "$PF/t.jsonl" --base "$PF_HEAD"
[ "$RC" -eq 0 ] && ok "the plan written against the base is green against the base" || fail "base run red: $OUT"
git -C "$PF" checkout -q -- a.txt
pf "$PF/plan.md" "$PF/t.jsonl" --base no-such-ref
[ "$RC" -ne 0 ] && printf '%s' "$ERR" | grep -q 'does not resolve' \
  && ok "a base that does not resolve is an error, never a silent fall back" || fail "bad base tolerated: $ERR"

# Scope: a path that does not exist must be declared as a new file.
sed 's/^b\.txt$/nowhere.txt/' "$PF/plan.md" > "$PF/plan-scope.md"
pf "$PF/plan-scope.md" "$PF/t.jsonl"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'nowhere.txt does not exist and is not declared' \
  && ok "an invented scope path is named" || fail "invented path passed: $OUT"
printf '%s' "$OUT" | grep -q 'c-new.txt does not exist' \
  && fail "a declared new file was treated as missing" || ok "a declared new file is exempt"

# Acceptance numbering: 1..N, no gap, no repeat.
sed 's/^| 2 | c | d |$/| 4 | c | d |/' "$PF/plan.md" > "$PF/plan-acc.md"
pf "$PF/plan-acc.md" "$PF/t.jsonl"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'acceptance numbers are not' \
  && ok "a gap in the acceptance numbering is caught" || fail "numbering gap passed: $OUT"

# Declared corrections: the literal must be there BEFORE the work and gone at the close. This is
# the rule that turns "I fixed it" from a sentence into something a machine checks.
sed 's/`beta line two`/`beta line NEVER`/' "$PF/plan.md" > "$PF/plan-corr.md"
pf "$PF/plan-corr.md" "$PF/t.jsonl"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'is not the case' \
  && ok "a correction of text that is not there is rejected" || fail "phantom correction passed: $OUT"
pf "$PF/plan.md" "$PF/t.jsonl" --closing
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'correction NOT DONE: b.txt' \
  && ok "at the close, an undone correction is named" || fail "undone correction passed: $OUT"
printf 'beta line one\nbeta DONE\n' > "$PF/b.txt"
pf "$PF/plan.md" "$PF/t.jsonl" --closing
[ "$RC" -eq 0 ] && ok "at the close, the correction actually made passes" || fail "done correction rejected: $OUT"
# With a base, the closing still reads the TREE for corrections: the base is where the old text
# lives by definition, and reading it there reported every correction NOT DONE, forever (measured
# 2026-09-14 on the plan of 0.6.1 itself: 42 of 42).
pf "$PF/plan.md" "$PF/t.jsonl" --closing --base "$PF_HEAD"
[ "$RC" -eq 0 ] && ok "at the close with a base, the correction is read in the tree, where it was made" || fail "the closing read the base: $OUT"
git -C "$PF" checkout -q -- b.txt

# An impact sweep command that was never run is a sweep that was narrated.
tr_write "$PF/t-nosweep.jsonl" 'cat a.txt' 'cat b.txt'
pf "$PF/plan.md" "$PF/t-nosweep.jsonl"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'not in the session transcript' \
  && ok "a sweep command that was never run is named" || fail "narrated sweep passed: $OUT"

# And with no transcript at all, nothing about reading can be proved -- which is the whole point.
pf "$PF/plan.md" ""
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'no transcript given' \
  && ok "without a transcript the pre-flight refuses to take the plan's word" || fail "no-transcript passed: $OUT"

rw_end
