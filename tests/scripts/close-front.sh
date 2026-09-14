#!/usr/bin/env bash
# close-front
# Run alone: bash tests/scripts/close-front.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── close-front: dry-run then apply with link rewrite ───────────────────────
section "close-front.sh"
CF="$TMP/cf"; mkdir -p "$CF"; git -C "$CF" init -q; git -C "$CF" config user.email t@t; git -C "$CF" config user.name t
bash skills/document/scripts/docs-init.sh "$CF" >/dev/null
printf 'status: accepted\n# old front\n' > "$CF/docs/plans/2026-01-01-0900-front.md"
printf 'status: accepted\nsee [front](../plans/2026-01-01-0900-front.md)\n' > "$CF/docs/decisions/2026-01-01-1000-ref.md"
git -C "$CF" add -A; git -C "$CF" commit -q -m base
bash skills/close/scripts/close-front.sh legacy docs/plans/2026-01-01-0900-front.md --root "$CF" > "$TMP/cf-dry.log"
[ -f "$CF/docs/plans/2026-01-01-0900-front.md" ] && grep -q 'git mv' "$TMP/cf-dry.log" && grep -q '1 rewrite' "$TMP/cf-dry.log" && ok "dry-run lists the move and the rewrite, changes nothing" || fail "dry-run wrong: $(cat "$TMP/cf-dry.log")"
bash skills/close/scripts/close-front.sh legacy docs/plans/2026-01-01-0900-front.md --root "$CF" --apply > "$TMP/cf-apply.log" 2>&1 && ok "apply moves the file and docs-check passes" || { fail "apply failed"; cat "$TMP/cf-apply.log"; }
[ -f "$CF/docs/history/legacy/2026-01-01-0900-front.md" ] && grep -q '(../history/legacy/2026-01-01-0900-front.md)' "$CF/docs/decisions/2026-01-01-1000-ref.md" && ok "link rewritten to the new location" || fail "link not rewritten"

rw_end
