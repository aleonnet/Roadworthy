#!/usr/bin/env bash
# pointers-check
# Run alone: bash tests/scripts/pointers-check.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── pointers-check ──────────────────────────────────────────────────────────
section "pointers-check.sh"
PC="$TMP/pc"; mkdir -p "$PC/docs" "$PC/mem"
printf 'Read `docs/a.md` and `tools/x.sh`.\n' > "$PC/CLAUDE.md"; : > "$PC/docs/a.md"
! bash skills/document/scripts/pointers-check.sh "$PC/CLAUDE.md" --root "$PC" >/dev/null 2>&1 && ok "cited path that does not exist fails" || fail "missing cited path passed"
mkdir -p "$PC/tools"; : > "$PC/tools/x.sh"
bash skills/document/scripts/pointers-check.sh "$PC/CLAUDE.md" --root "$PC" >/dev/null && ok "all cited paths exist → passes" || fail "valid citations rejected"
printf '# idx\n- [one](feedback_one.md)\n' > "$PC/mem/MEMORY.md"; : > "$PC/mem/feedback_one.md"; : > "$PC/mem/feedback_orphan.md"
! bash skills/document/scripts/pointers-check.sh "$PC/CLAUDE.md" --root "$PC" --memory "$PC/mem" >/dev/null 2>&1 && ok "orphan memory file fails" || fail "orphan passed"
rm "$PC/mem/feedback_orphan.md"; printf -- '- [gone](feedback_gone.md)\n' >> "$PC/mem/MEMORY.md"
! bash skills/document/scripts/pointers-check.sh "$PC/CLAUDE.md" --root "$PC" --memory "$PC/mem" >/dev/null 2>&1 && ok "index line without file fails" || fail "dangling index line passed"
# An index split by theme: MEMORY.md links a sub-index, the sub-index links the leaf (measured 2026-09-07:
# 51 false orphans on a project whose history lived in one sub-index).
printf '# idx\n- [one](feedback_one.md)\n- [history](project_history.md)\n' > "$PC/mem/MEMORY.md"
printf -- '- [leaf](project_leaf.md)\n' > "$PC/mem/project_history.md"; : > "$PC/mem/project_leaf.md"
bash skills/document/scripts/pointers-check.sh "$PC/CLAUDE.md" --root "$PC" --memory "$PC/mem" >/dev/null && ok "memory file reached through a sub-index is not an orphan" || fail "sub-indexed memory counted as orphan"
: > "$PC/mem/project_orphan.md"
! bash skills/document/scripts/pointers-check.sh "$PC/CLAUDE.md" --root "$PC" --memory "$PC/mem" >/dev/null 2>&1 && ok "a file no index reaches still fails" || fail "orphan passed next to a sub-index"
rm "$PC/mem/project_orphan.md"

rw_end
