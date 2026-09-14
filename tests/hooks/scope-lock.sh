#!/usr/bin/env bash
# scope-lock
# Run alone: bash tests/hooks/scope-lock.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── scope-lock ───────────────────────────────────────────────────────────────
section "scope-lock"
REPO="$TMP/repo"; mkdir -p "$REPO/.roadworthy" "$REPO/src" "$REPO/docs" "$REPO/src/deep"
git -C "$REPO" init -q
printf '# scope\nsrc/**\n' > "$REPO/.roadworthy/scope"
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$REPO/docs/readme.md\"}}"
denied && ok "edit outside scope denied" || fail "outside scope not denied"
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$REPO/src/a.dart\"}}"
! denied && ok "edit inside scope allowed" || fail "inside scope denied"
# The foundation of the front is NOT editable by hand: exempting the whole .roadworthy/
# directory put the scope, the gates and the ledgers inside the blind spot of the guard that
# exists to protect them. Human configuration of the project stays editable, by name.
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$REPO/.roadworthy/scope\"}}"
denied && ok "the scope file itself is NOT editable by hand" || fail "scope file still editable"
for cfg in docs.json protected overnight-rules; do
  run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$REPO/.roadworthy/$cfg\"}}"
  ! denied || fail "human configuration $cfg denied"
done
ok "human configuration (docs.json, protected, overnight-rules) stays editable"
# The scope belongs to the project, so the lock has to hold from a subdirectory too. Read at
# the session cwd it was simply absent one level down, and every edit passed.
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$REPO/src/deep\",\"tool_input\":{\"file_path\":\"$REPO/docs/readme.md\"}}"
denied && ok "the lock holds from a subdirectory of the project" || fail "lock inert from a subdirectory"
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$REPO/src/deep\",\"tool_input\":{\"file_path\":\"$REPO/src/a.dart\"}}"
! denied && ok "and still allows what is inside the scope from there" || fail "in-scope edit denied from a subdirectory"
# The plan lives outside the project, in the plans directory: the lock must not deny the rite's
# own artefact. Measured in the field on 2026-09-08 and again on 2026-09-13, in two projects:
# denied there, the agent's only way out was widening the scope by hand.
PLANS_SB="$TMP/plansdir"; mkdir -p "$PLANS_SB/sub"
CLAUDE_PLUGIN_OPTION_PLANS_DIR="$PLANS_SB" run_hook scope-lock "{\"tool_name\":\"Write\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$PLANS_SB/my-plan.md\"}}"
! denied && ok "the plan file (plans_dir) is editable while the lock is on" || fail "plan file denied by the scope lock"
CLAUDE_PLUGIN_OPTION_PLANS_DIR="$PLANS_SB" run_hook scope-lock "{\"tool_name\":\"Write\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$PLANS_SB/sub/my-plan.md\"}}"
! denied && ok "a subdirectory of the plans directory too" || fail "plans subdirectory denied"
CLAUDE_PLUGIN_OPTION_PLANS_DIR="$PLANS_SB" run_hook scope-lock "{\"tool_name\":\"Write\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$TMP/elsewhere.md\"}}"
denied && ok "another path outside the project is still denied" || fail "outside path passed"
rm "$REPO/.roadworthy/scope"
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$REPO/docs/readme.md\"}}"
! denied && ok "no scope file → lock inactive" || fail "lock active without scope file"

rw_end
