#!/usr/bin/env bash
# overnight-guard
# Run alone: bash tests/hooks/overnight-guard.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── overnight-guard: inert without the marker, denies publishing with it ───
section "overnight-guard"
ON="$TMP/on"; mkdir -p "$ON/.roadworthy"; git -C "$ON" init -q; git -C "$ON" config user.email t@t; git -C "$ON" config user.name t
run_hook overnight-guard "{\"tool_name\":\"Bash\",\"cwd\":\"$ON\",\"tool_input\":{\"command\":\"git push origin main\"}}"
! denied && [ "$RC" -eq 0 ] && ok "no marker: git push untouched" || fail "no marker: push denied"
echo '{"topic":"t"}' > "$ON/.roadworthy/overnight"
run_hook overnight-guard "{\"tool_name\":\"Bash\",\"cwd\":\"$ON\",\"tool_input\":{\"command\":\"git push origin main\"}}"
denied && printf '%s' "$OUT" | grep -q 'overnight' && ok "marker: git push denied, reason names overnight mode" || fail "marker: push passed"
run_hook overnight-guard "{\"tool_name\":\"Bash\",\"cwd\":\"$ON\",\"tool_input\":{\"command\":\"cd $ON && git -C $ON merge feature\"}}"
denied && ok "marker: git -C … merge denied" || fail "marker: merge passed"
run_hook overnight-guard "{\"tool_name\":\"Bash\",\"cwd\":\"$ON\",\"tool_input\":{\"command\":\"gh pr merge 12\"}}"
denied && ok "marker: gh pr merge denied" || fail "marker: gh pr merge passed"
run_hook overnight-guard "{\"tool_name\":\"Bash\",\"cwd\":\"$ON\",\"tool_input\":{\"command\":\"git commit -m m && pytest -q\"}}"
! denied && ok "marker: commit and tests untouched" || fail "marker: ordinary command denied"
printf '# rules\ndeny: pio run .* -t upload\ndeny: (^|[;&| ])sudo( |$)\nfreeze: pubspec.yaml\nfreeze: CHANGELOG.md\n' > "$ON/.roadworthy/overnight-rules"
run_hook overnight-guard "{\"tool_name\":\"Bash\",\"cwd\":\"$ON\",\"tool_input\":{\"command\":\"pio run -e board -t upload\"}}"
denied && printf '%s' "$OUT" | grep -q 'pio run' && ok "deny: rule denied, reason names the rule" || fail "deny: rule passed"
run_hook overnight-guard "{\"tool_name\":\"Bash\",\"cwd\":\"$ON\",\"tool_input\":{\"command\":\"pio run -e board\"}}"
! denied && ok "deny: rule does not match a plain build" || fail "deny: rule over-matched"
printf 'deny: (unclosed\n' > "$ON/.roadworthy/overnight-rules"
run_hook overnight-guard "{\"tool_name\":\"Bash\",\"cwd\":\"$ON\",\"tool_input\":{\"command\":\"echo hello\"}}"
denied && printf '%s' "$OUT" | grep -q 'internal error' && ok "malformed rule fails closed" || fail "malformed rule passed silently"
printf 'freeze: pubspec.yaml\nfreeze: CHANGELOG.md\n' > "$ON/.roadworthy/overnight-rules"
SUB="$ON/lib"; mkdir -p "$SUB"
run_hook overnight-guard "{\"tool_name\":\"Bash\",\"cwd\":\"$SUB\",\"tool_input\":{\"command\":\"git push\"}}"
denied && ok "marker found from a subdirectory of the repository" || fail "marker not found from a subdirectory"
# The night belongs to the repository the COMMAND acts on. Resolving from the session cwd
# denied a push to an unmarked repository just because the session stood in a marked one.
OTHER="$TMP/othernight"; mkdir -p "$OTHER"; git -C "$OTHER" init -q
run_hook overnight-guard "{\"tool_name\":\"Bash\",\"cwd\":\"$ON\",\"tool_input\":{\"command\":\"git -C $OTHER push origin main\"}}"
! denied && ok "a push to another, unmarked repository passes from inside a marked one" || fail "the night denied another repository"
run_hook overnight-guard "{\"tool_name\":\"Bash\",\"cwd\":\"$OTHER\",\"tool_input\":{\"command\":\"git -C $ON push origin main\"}}"
denied && ok "and a push to the MARKED repository is denied from outside it" || fail "the night missed the repository the command attacks"

rw_end
