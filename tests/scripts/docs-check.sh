#!/usr/bin/env bash
# docs-check
# Run alone: bash tests/scripts/docs-check.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── docs-check ───────────────────────────────────────────────────────────────
section "docs-check.sh"
D="$TMP/docs"; mkdir -p "$D"
printf 'status: accepted\n# ok\n[link](2026-01-02-1000-other.md)\n' > "$D/2026-01-01-0900-first.md"
printf 'status: superseded by 2026-01-01-0900-first.md\n' > "$D/2026-01-02-1000-other.md"
bash skills/document/scripts/docs-check.sh "$D" >/dev/null && ok "valid tree passes" || fail "valid tree rejected"
printf 'status: approved\n' > "$D/2026-01-03-1100-bad-status.md"
! bash skills/document/scripts/docs-check.sh "$D" >/dev/null 2>&1 && ok "status outside vocabulary fails" || fail "bad status passed"
rm "$D/2026-01-03-1100-bad-status.md"
printf 'status: accepted\n' > "$D/2026-01-03-notes-v2.md"
! bash skills/document/scripts/docs-check.sh "$D" >/dev/null 2>&1 && ok "dated name outside pattern fails" || fail "bad name passed"
rm "$D/2026-01-03-notes-v2.md"
printf 'status: accepted\nplan: 2026-01-01-0900-first.md\nVERDICT: APPROVED\n' > "$D/2026-01-01-0900-first.review.md"
bash skills/document/scripts/docs-check.sh "$D" >/dev/null && ok "review companion (.review.md) next to the plan passes" || fail "review companion rejected"
printf 'status: accepted\n' > "$D/2026-01-01-0900-first.notes.md"
! bash skills/document/scripts/docs-check.sh "$D" >/dev/null 2>&1 && ok "other dotted suffix still fails" || fail "dotted suffix passed"
rm "$D/2026-01-01-0900-first.notes.md"
# The plan skill writes `<plan><review_suffix>`: a plan `x.plan.md` gets `x.plan.review.md`, and the
# reviewer writes `plan:` / `round:` / `VERDICT:` — no `status:` line (measured 2026-09-07 on a project).
printf 'status: accepted\n' > "$D/2026-01-06-1400-work.plan.md"
printf 'plan: 2026-01-06-1400-work.plan.md\nround: 1\nVERDICT: APPROVED\n' > "$D/2026-01-06-1400-work.plan.review.md"
bash skills/document/scripts/docs-check.sh "$D" >/dev/null && ok "the plan skill's review (x.plan.review.md, VERDICT instead of status) passes" || fail "plan review companion rejected"
printf 'plan: 2026-01-06-1400-work.plan.md\nround: 1\n' > "$D/2026-01-06-1400-work.plan.review.md"
! bash skills/document/scripts/docs-check.sh "$D" >/dev/null 2>&1 && ok "review companion without a VERDICT line fails" || fail "verdict-less review passed"
rm "$D/2026-01-06-1400-work.plan.md" "$D/2026-01-06-1400-work.plan.review.md"
printf 'status: superseded by 2026-09-09-0000-nope.md\n' > "$D/2026-01-04-1200-dangling.md"
! bash skills/document/scripts/docs-check.sh "$D" >/dev/null 2>&1 && ok "dangling superseded-by fails" || fail "dangling passed"
rm "$D/2026-01-04-dangling.md" 2>/dev/null || rm "$D/2026-01-04-1200-dangling.md"
printf 'status: accepted\n[x](missing.md)\n' > "$D/2026-01-05-1300-broken-link.md"
! bash skills/document/scripts/docs-check.sh "$D" >/dev/null 2>&1 && ok "broken relative link fails" || fail "broken link passed"

# ── docs-check v2: role-aware rules ─────────────────────────────────────────
section "docs-check.sh (roles)"
DI="$TMP/di-roles"; fx_docs_tree "$DI"
bash skills/document/scripts/docs-check.sh "$DI/docs" >/dev/null && ok "fresh tree passes" || fail "fresh tree rejected"
printf 'status: accepted\n# done plan\n' > "$DI/docs/plans/done/2026-01-01-0900-x.plan.md"
! bash skills/document/scripts/docs-check.sh "$DI/docs" >/dev/null 2>&1 && ok "concluded plan without index line fails" || fail "unindexed done plan passed"
printf -- '- [x](2026-01-01-0900-x.plan.md)\n' >> "$DI/docs/plans/done/README.md"
bash skills/document/scripts/docs-check.sh "$DI/docs" >/dev/null && ok "indexed done plan passes" || fail "indexed done plan rejected"
printf 'status: accepted\n' > "$DI/docs/plans/2026-01-01-0900-handoff-a.md"; printf 'status: accepted\n' > "$DI/docs/plans/2026-01-02-0900-handoff-b.md"
! bash skills/document/scripts/docs-check.sh "$DI/docs" >/dev/null 2>&1 && ok "two live handoffs fail" || fail "two live handoffs passed"
printf 'status: superseded by 2026-01-02-0900-handoff-b.md\n' > "$DI/docs/plans/2026-01-01-0900-handoff-a.md"
bash skills/document/scripts/docs-check.sh "$DI/docs" >/dev/null && ok "superseded older handoff passes" || fail "superseded handoff rejected"
# project status words: only accepted when declared in docs.json
printf 'status: aceito\n# adr\n' > "$DI/docs/decisions/2026-01-03-0900-adr.md"
! bash skills/document/scripts/docs-check.sh "$DI/docs" >/dev/null 2>&1 && ok "undeclared project word rejected" || fail "undeclared status word passed"
python3 - "$DI/.roadworthy/docs.json" <<'PY'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["status"]={"accepted":"aceito","superseded by":"superado por"}; json.dump(d,open(p,"w"))
PY
# the mapping REPLACES the English words (one vocabulary per project): convert the fixture
python3 - "$DI/docs" <<'PY'
import os,sys
for d,_,fs in os.walk(sys.argv[1]):
    for f in fs:
        p=os.path.join(d,f); t=open(p).read()
        open(p,"w").write(t.replace("status: accepted","status: aceito").replace("status: superseded by","status: superado por"))
PY
bash skills/document/scripts/docs-check.sh "$DI/docs" >/dev/null && ok "declared project word accepted" || fail "declared status word rejected"
printf 'status: accepted\n# adr\n' > "$DI/docs/decisions/2026-01-05-0900-english.md"
! bash skills/document/scripts/docs-check.sh "$DI/docs" >/dev/null 2>&1 && ok "English word rejected once the project declared its own" || fail "English word still accepted under a project vocabulary"
rm -f "$DI/docs/decisions/2026-01-05-0900-english.md"
printf 'status: superado por 2026-01-02-0900-handoff-b.md\n' > "$DI/docs/plans/2026-01-01-0900-handoff-a.md"
bash skills/document/scripts/docs-check.sh "$DI/docs" >/dev/null && ok "superseded-by in the project words recognised" || fail "project superseded-by not recognised"
printf 'status: superado por 2026-01-09-0900-nao-existe.md\n' > "$DI/docs/plans/2026-01-01-0900-handoff-a.md"
! bash skills/document/scripts/docs-check.sh "$DI/docs" >/dev/null 2>&1 && ok "dangling project superseded-by fails" || fail "dangling project superseded-by passed"
printf 'status: superado por 2026-01-02-0900-handoff-b.md\n' > "$DI/docs/plans/2026-01-01-0900-handoff-a.md"
# index line with ./ prefix
printf 'status: aceito\n# done plan\n' > "$DI/docs/plans/done/2026-01-04-0900-y.plan.md"; printf -- '- [y](./2026-01-04-0900-y.plan.md)\n' >> "$DI/docs/plans/done/README.md"
bash skills/document/scripts/docs-check.sh "$DI/docs" >/dev/null && ok "index link with ./ prefix accepted" || fail "./ index link rejected"
# handoff before the --since cut is legacy, not live
printf 'status: aceito\n' > "$DI/docs/plans/2025-12-01-0900-handoff-old.md"
! bash skills/document/scripts/docs-check.sh "$DI/docs" >/dev/null 2>&1 && ok "pre-cut handoff counts as live without --since" || fail "pre-cut handoff ignored without --since"
bash skills/document/scripts/docs-check.sh "$DI/docs" --since 2026-01-01 >/dev/null && ok "pre-cut handoff exempt with --since" || fail "pre-cut handoff still live with --since"

rw_end
