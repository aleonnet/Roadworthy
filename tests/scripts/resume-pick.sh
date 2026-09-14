#!/usr/bin/env bash
# resume-pick
# Run alone: bash tests/scripts/resume-pick.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── resume-pick: newest by NAME, never by mtime ─────────────────────────────
section "resume-pick.sh"
DI="$TMP/di-resume"; fx_docs_tree "$DI"
python3 - "$DI/.roadworthy/docs.json" <<'PYJ'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["status"]={"accepted":"aceito","superseded by":"superado por"}; json.dump(d,open(p,"w"))
PYJ
printf 'status: accepted\n' > "$DI/docs/plans/2026-01-01-0900-handoff-a.md"
printf 'status: accepted\n' > "$DI/docs/plans/2026-01-02-0900-handoff-b.md"
touch "$DI/docs/plans/2026-01-01-0900-handoff-a.md"   # older handoff, newer mtime
[ "$(bash skills/resume/scripts/resume-pick.sh "$DI")" = "$DI/docs/plans/2026-01-02-0900-handoff-b.md" ] && ok "picks the newest by name despite mtime" || fail "resume-pick chose by mtime"
printf 'status: superseded by 2026-01-01-0900-handoff-a.md\n' > "$DI/docs/plans/2026-01-02-0900-handoff-b.md"
! bash skills/resume/scripts/resume-pick.sh "$DI" >/dev/null 2>&1 && ok "superseded-by pointing at something older fails" || fail "backward pointer accepted"
printf 'status: accepted\n' > "$DI/docs/plans/2026-01-02-0900-handoff-b.md"
# The pointer has to be READ in the word the project declares -- here Portuguese, set above in
# this tree's docs.json. A pointer the script cannot read is a pointer it ignores, and ignoring it
# means handing back the SUPERSEDED hand-off as if it were current (measured 2026-09-07 on a real
# project: the newest file by name was marked "superado por" and the script printed it anyway).
printf 'status: superado por 2026-01-01-0900-handoff-a.md\n' > "$DI/docs/plans/2026-01-02-0900-handoff-b.md"
! bash skills/resume/scripts/resume-pick.sh "$DI" >/dev/null 2>&1 \
  && ok "a superseded-by written in the project word is READ, not ignored" || fail "resume ignored the project vocabulary and returned the superseded hand-off"
printf 'status: accepted\n' > "$DI/docs/plans/2026-01-02-0900-handoff-b.md"

rw_end
