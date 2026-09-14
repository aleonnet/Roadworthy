#!/usr/bin/env bash
# overnight
# Run alone: bash tests/scripts/overnight.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── overnight scripts: start refuses, entry measures, close needs FRESH ─────
section "overnight scripts"
OV="$TMP/ov"; mkdir -p "$OV"; git -C "$OV" init -q; git -C "$OV" config user.email t@t; git -C "$OV" config user.name t
bash skills/document/scripts/docs-init.sh "$OV" >/dev/null
printf 'true\n' > "$OV/.roadworthy/gates"; printf 'docs/**\n' > "$OV/.roadworthy/scope"
printf '# plan\n\n## Overnight policy\n- Decided at night, with a source: anything established.\n- Reserved for the user: none.\n' > "$OV/docs/plans/2026-01-02-0100-night.md"
git -C "$OV" add -A; git -C "$OV" commit -q -m base
S="$ROOT/skills/overnight/scripts"
! (cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0100-night.md night) >/dev/null 2>"$TMP/ov1" && grep -q 'no review' "$TMP/ov1" && ok "start refused without a review" || fail "start without review: $(cat "$TMP/ov1")"
sha="$(shasum -a 256 "$OV/docs/plans/2026-01-02-0100-night.md" | cut -d' ' -f1)"
printf 'plan: 2026-01-02-0100-night.md\nplan-sha256: %s\nVERDICT: REJECTED\n' "$sha" > "$OV/docs/plans/2026-01-02-0100-night.review.md"
git -C "$OV" add -A; git -C "$OV" commit -q -m rejected
! (cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0100-night.md night) >/dev/null 2>"$TMP/ov2" && grep -q 'not APPROVED' "$TMP/ov2" && ok "start refused on a rejected review" || fail "start on rejected review: $(cat "$TMP/ov2")"
printf '# plan\n' > "$OV/docs/plans/2026-01-02-0300-bare.md"
! (cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0300-bare.md night) >/dev/null 2>"$TMP/ov2b" && grep -q '3 precondition' "$TMP/ov2b" && grep -q 'no review' "$TMP/ov2b" && grep -q 'Overnight policy' "$TMP/ov2b" && grep -q 'dirty' "$TMP/ov2b" && ok "start lists EVERY missing precondition at once (review, policy, dirty tree)" || fail "preconditions not listed together: $(cat "$TMP/ov2b")"
rm "$OV/docs/plans/2026-01-02-0300-bare.md"
printf 'plan: 2026-01-02-0100-night.md\nVERDICT: APPROVED\n' > "$OV/docs/plans/2026-01-02-0100-night.review.md"
! (cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0100-night.md night) >/dev/null 2>"$TMP/ov3" && grep -q 'dirty' "$TMP/ov3" && ok "start refused on a dirty tree (approved review not committed)" || fail "start on dirty tree: $(cat "$TMP/ov3")"
git -C "$OV" add -A; git -C "$OV" commit -q -m review
printf '# plan without policy\n' > "$OV/docs/plans/2026-01-02-0200-nopolicy.md"
sha2="$(shasum -a 256 "$OV/docs/plans/2026-01-02-0200-nopolicy.md" | cut -d' ' -f1)"
printf 'plan: x\nplan-sha256: %s\nVERDICT: APPROVED\n' "$sha2" > "$OV/docs/plans/2026-01-02-0200-nopolicy.review.md"
git -C "$OV" add -A; git -C "$OV" commit -q -m nopolicy
! (cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0200-nopolicy.md night) >/dev/null 2>"$TMP/ov4" && grep -q 'Overnight policy' "$TMP/ov4" && ok "start refused on a plan without the Overnight policy section" || fail "start without policy section"
printf '# plano\n\n## Política da madrugada\n- nada.\n' > "$OV/docs/plans/2026-01-02-0400-pt.md"
printf 'plan: 2026-01-02-0400-pt.md\nVERDICT: APPROVED\n' > "$OV/docs/plans/2026-01-02-0400-pt.review.md"
! (cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0400-pt.md night) >/dev/null 2>"$TMP/ov4b" && grep -q 'dirty' "$TMP/ov4b" && ! grep -q 'Overnight policy' "$TMP/ov4b" && ok "a plan titled 'Política da madrugada' is refused only for what is really missing (dirty tree), not for the title" || fail "PT title refused: $(cat "$TMP/ov4b")"
rm "$OV/docs/plans/2026-01-02-0400-pt.md" "$OV/docs/plans/2026-01-02-0400-pt.review.md"
t0="$(python3 -c 'import time; print(int(time.time()*1000))')"
diary="$(cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0100-night.md night | tail -1)"
t1="$(python3 -c 'import time; print(int(time.time()*1000))')"
[ -f "$OV/.roadworthy/overnight" ] && [ -f "$OV/$diary" ] && ok "start writes the marker and the diary ($diary)" || fail "start did not write marker/diary"
# The diary is written by a script, so its status line is the project's word, never hardcoded.
head -1 "$OV/$diary" | grep -q '^status: accepted$' \
  && ok "the diary carries the status word (English here: this project declares none)" || fail "diary status line: $(head -1 "$OV/$diary")"
DIARY_PT="$(sed -e "s|{{status}}|aceito|" "$ROOT/skills/overnight/templates/diary.md" | head -1)"
[ "$DIARY_PT" = "status: aceito" ] && ok "the diary template takes the word from the placeholder, not from a literal" || fail "diary template still hardcodes a word: $DIARY_PT"
HANDOFF_PT="$(sed -e "s|{{status}}|aceito|" "$ROOT/skills/overnight/templates/handoff.md" | head -1)"
[ "$HANDOFF_PT" = "status: aceito" ] && ok "and so does the hand-off template" || fail "hand-off template still hardcodes a word: $HANDOFF_PT"
ms="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["started_ms"])' "$OV/.roadworthy/overnight")"
[ "$ms" -ge "$t0" ] && [ "$ms" -le "$t1" ] && ok "started_ms was measured by the script (within the test's clock window)" || fail "started_ms outside window: $t0 ≤ $ms ≤ $t1"
! (cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0100-night.md night) >/dev/null 2>"$TMP/ov5" && grep -q 'already on' "$TMP/ov5" && ok "start refused while the marker exists" || fail "double start accepted"
! (cd "$OV" && bash "$S/overnight-entry.sh" --phase F1 --decision d --reason r) >/dev/null 2>"$TMP/ov6" && grep -q -- '--source' "$TMP/ov6" && ok "entry refused without a source" || fail "entry without source accepted"
# A source has to be openable. "RFC 0000 §1" was accepted here for a year and is exactly the
# shape the rule exists to refuse: a citation nobody can follow.
! (cd "$OV" && bash "$S/overnight-entry.sh" --phase F1 --decision d --reason r --source "RFC 0000 §1") >/dev/null 2>&1 \
  && ok "a source that is only a sentence is refused" || fail "unopenable source accepted"
! (cd "$OV" && bash "$S/overnight-entry.sh" --phase F1 --decision d --reason r --source "docs/nao-existe.md") >/dev/null 2>&1 \
  && ok "a path that does not exist is refused" || fail "missing path accepted as a source"
(cd "$OV" && bash "$S/overnight-entry.sh" --phase F1 --decision "use X" --reason "spec says so" --source "https://example.invalid/spec#1" --ratify) >/dev/null \
  && grep -q -E '^- `[0-9]{13}` · [0-9T:Z-]+ · \*\*F1\*\* · use X · reason: spec says so · source: https://example.invalid/spec#1 · ratify in the morning$' "$OV/$diary" \
  && ok "entry carries epoch ms + ISO taken by the script, under Decisions" || fail "entry format: $(grep 'use X' "$OV/$diary")"
(cd "$OV" && bash "$S/overnight-entry.sh" --phase F1 --decision d2 --reason r --source "docs/plans/2026-01-02-0100-night.md") >/dev/null \
  && ok "an existing file is a source" || fail "existing file refused as a source"
(cd "$OV" && bash "$S/overnight-entry.sh" --phase F1 --decision d3 --reason r --source HEAD) >/dev/null \
  && ok "a git ref that resolves is a source" || fail "git ref refused as a source"
(cd "$OV" && bash "$S/overnight-entry.sh" --blocker "pricing is the user's") >/dev/null && python3 - "$OV/$diary" <<'PY' && ok "blocker lands under its own section" || fail "blocker section"
import sys; t=open(sys.argv[1]).read(); i=t.index("## Blockers for the morning"); j=t.index("## Delivery"); sys.exit(0 if "pricing is the user's" in t[i:j] else 1)
PY
(cd "$OV" && bash "$S/overnight-entry.sh" --phase-done F1 --sha abc1234 --gates "suite green") >/dev/null && grep -q '^| F1 | `abc1234` | suite green |' "$OV/$diary" && [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["phase"])' "$OV/.roadworthy/overnight")" = "F1" ] && ok "phase ledger row; marker phase follows" || fail "phase ledger row / marker phase"
export ROADWORTHY_DATA="$TMP/ovdata"
! (cd "$OV" && bash "$S/overnight-close.sh") >/dev/null 2>"$TMP/ov7" && grep -q 'dirty' "$TMP/ov7" && ok "close refused on a dirty tree (the diary is uncommitted)" || fail "close on dirty tree"
git -C "$OV" add -A; git -C "$OV" commit -q -m diary
! (cd "$OV" && bash "$S/overnight-close.sh") >/dev/null 2>"$TMP/ov8" && grep -q -E 'STALE|MISSING' "$TMP/ov8" && [ -f "$OV/.roadworthy/overnight" ] && ok "close refused while a gate is MISSING; marker kept" || fail "close without evidence accepted"
# A night must not close with nothing measured: with no gate declared, close.sh fails and the
# refusal reaches here instead of being read as "every gate FRESH".
printf '# no gate declared\n' > "$OV/.roadworthy/gates"
git -C "$OV" -c user.email=t@t -c user.name=t commit -qam 'no gates'
! (cd "$OV" && bash "$S/overnight-close.sh") >/dev/null 2>"$TMP/ov9" && grep -q 'no gate' "$TMP/ov9" && [ -f "$OV/.roadworthy/overnight" ] && ok "the night refuses to close with no gate declared; marker kept" || fail "night closed with nothing measured: $(cat "$TMP/ov9")"
printf 'true\n' > "$OV/.roadworthy/gates"
git -C "$OV" -c user.email=t@t -c user.name=t commit -qam 'gates back'
# The night started against a specific plan, and its hash has been recorded since 0.3.0 with
# nobody reading it: the plan could be rewritten mid-night and the morning would never know.
printf '# plan\n\n## Overnight policy\n- rewritten mid-night.\n' > "$OV/docs/plans/2026-01-02-0100-night.md"
git -C "$OV" -c user.email=t@t -c user.name=t commit -qam 'plan rewritten'
! (cd "$OV" && bash "$S/overnight-close.sh" --run) >/dev/null 2>"$TMP/ovsha" && grep -q 'the plan changed during the night' "$TMP/ovsha" \
  && ok "the night refuses to close when the plan changed under it" || fail "plan rewritten mid-night and the close did not notice: $(cat "$TMP/ovsha")"
python3 - "$OV/.roadworthy/overnight" "$OV/docs/plans/2026-01-02-0100-night.md" <<'PY'
import hashlib, json, sys
m = json.load(open(sys.argv[1]))
m["plan_sha256"] = hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest()
json.dump(m, open(sys.argv[1], "w"), indent=1)
PY
git -C "$OV" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1 || true
git -C "$OV" -c user.email=t@t -c user.name=t commit -qam 'marker' >/dev/null 2>&1 || true
handoff="$(cd "$OV" && bash "$S/overnight-close.sh" --run | tail -1)"
[ -f "$OV/$handoff" ] && [ ! -f "$OV/.roadworthy/overnight" ] && grep -q "pricing is the user's" "$OV/$handoff" && grep -q '| ov | ' "$OV/$handoff" && ok "close with FRESH gates writes the hand-off with the blockers and removes the marker" || fail "close --run: $handoff"
unset ROADWORTHY_DATA

rw_end
