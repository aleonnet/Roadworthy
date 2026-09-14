#!/usr/bin/env bash
# protect-paths
# Run alone: bash tests/hooks/protect-paths.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── protect-paths ────────────────────────────────────────────────────────────
section "protect-paths"
E='{"tool_name":"Edit","cwd":"/repo","tool_input":{"file_path":"/repo/lib/ble/manager.dart"}}'
CLAUDE_PLUGIN_OPTION_PROTECTED_PATHS='lib/ble/**,**/permissions.dart' run_hook protect-paths "$E"
denied && ok "edit inside protected glob denied" || fail "protected glob not denied"
CLAUDE_PLUGIN_OPTION_PROTECTED_PATHS='lib/ble/**' run_hook protect-paths '{"tool_name":"Edit","cwd":"/repo","tool_input":{"file_path":"/repo/lib/ui/home.dart"}}'
! denied && [ "$RC" -eq 0 ] && ok "edit outside protected glob allowed" || fail "outside glob wrongly denied"
CLAUDE_PLUGIN_OPTION_PROTECTED_PATHS='**/permissions.dart' run_hook protect-paths '{"tool_name":"Write","cwd":"/repo","tool_input":{"file_path":"/repo/a/b/permissions.dart"}}'
denied && ok "** matches any depth" || fail "** depth"
# A glob is anchored at the root. A bare `README.md` used to match `docs/README.md` too, because
# the matcher fell back to searching at any separator -- which silently widened every scope and
# every protected list one level deeper than it was written.
CLAUDE_PLUGIN_OPTION_PROTECTED_PATHS='README.md' run_hook protect-paths '{"tool_name":"Edit","cwd":"/repo","tool_input":{"file_path":"/repo/README.md"}}'
denied && ok "a bare name matches at the root" || fail "bare name did not match at the root"
CLAUDE_PLUGIN_OPTION_PROTECTED_PATHS='README.md' run_hook protect-paths '{"tool_name":"Edit","cwd":"/repo","tool_input":{"file_path":"/repo/docs/README.md"}}'
! denied && ok "a bare name does NOT match one level down" || fail "bare name still matches at any depth"
CLAUDE_PLUGIN_OPTION_PROTECTED_PATHS='**/README.md' run_hook protect-paths '{"tool_name":"Edit","cwd":"/repo","tool_input":{"file_path":"/repo/docs/README.md"}}'
denied && ok "**/ is how you say any depth, and it still works" || fail "**/ regressed"
run_hook protect-paths "$E"
! denied && ok "empty option → guard inactive" || fail "empty option denied"

# ── protect-paths: project file ──────────────────────────────────────────────
section "protect-paths (.roadworthy/protected)"
PP="$TMP/pp"; mkdir -p "$PP/.roadworthy" "$PP/lib/auth"; printf '# protected\nlib/auth/**\n' > "$PP/.roadworthy/protected"
run_hook protect-paths "{\"tool_name\":\"Edit\",\"cwd\":\"$PP\",\"tool_input\":{\"file_path\":\"$PP/lib/auth/x.py\"}}"
denied && ok "project file glob denied without any user option" || fail "project protected file ignored"
run_hook protect-paths "{\"tool_name\":\"Edit\",\"cwd\":\"$PP\",\"tool_input\":{\"file_path\":\"$PP/lib/other.py\"}}"
! denied && ok "outside project globs allowed" || fail "outside project glob denied"
# Same reason as the scope: the project list lives at the top level.
git -C "$PP" init -q; mkdir -p "$PP/lib/auth/deep"
run_hook protect-paths "{\"tool_name\":\"Edit\",\"cwd\":\"$PP/lib/auth/deep\",\"tool_input\":{\"file_path\":\"$PP/lib/auth/x.py\"}}"
denied && ok "the project protected list holds from a subdirectory" || fail "project protected list inert from a subdirectory"

# ── protect-paths: overnight freeze ──────────────────────────────────────────
section "protect-paths (overnight freeze)"
ON="$TMP/pp-night"; fx_night "$ON"
fx_night_rules "$ON" "freeze: pubspec.yaml" "freeze: CHANGELOG.md"
SUB="$ON/lib"; mkdir -p "$SUB"
run_hook protect-paths "{\"tool_name\":\"Edit\",\"cwd\":\"$ON\",\"tool_input\":{\"file_path\":\"$ON/pubspec.yaml\"}}"
denied && printf '%s' "$OUT" | grep -q 'frozen for the night' && ok "frozen file denied with the marker" || fail "frozen file passed"
run_hook protect-paths "{\"tool_name\":\"Edit\",\"cwd\":\"$ON\",\"tool_input\":{\"file_path\":\"$ON/lib/a.dart\"}}"
! denied && ok "file outside the freeze list allowed" || fail "unfrozen file denied"
run_hook protect-paths "{\"tool_name\":\"Edit\",\"cwd\":\"$SUB\",\"tool_input\":{\"file_path\":\"$ON/pubspec.yaml\"}}"
denied && ok "frozen file denied from a subdirectory cwd (root = git top-level)" || fail "freeze fails open from a subdirectory"
rm -f "$ON/.roadworthy/overnight"
run_hook protect-paths "{\"tool_name\":\"Edit\",\"cwd\":\"$ON\",\"tool_input\":{\"file_path\":\"$ON/pubspec.yaml\"}}"
! denied && ok "without the marker the freeze list is inert" || fail "freeze applied without the marker"

rw_end
