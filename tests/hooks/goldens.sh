#!/usr/bin/env bash
# goldens
# Run alone: bash tests/hooks/goldens.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

section "goldens"
# Until now the suite only ever asked whether a fragment appeared in the output. That accepts a
# malformed answer containing the right characters and rejects a correct one formatted otherwise,
# so the SHAPE of what a guard returns -- the contract Claude Code actually consumes -- was never
# pinned by anything. tests/goldens/ holds it, and every guard is measured against it.
GD="$TMP/gold"; mkdir -p "$GD/.roadworthy"; git -C "$GD" init -q
PROJ="$HOME_SANDBOX/.claude/projects/-gold"; fx_memory_project "$PROJ"

CLAUDE_PLUGIN_OPTION_PROTECTED_PATHS='secret.txt' run_hook protect-paths "{\"tool_name\":\"Edit\",\"cwd\":\"$GD\",\"tool_input\":{\"file_path\":\"$GD/secret.txt\"}}"
golden deny-envelope.json && ok "protect-paths denies in the golden envelope" || fail "protect-paths envelope: $OUT"

printf 'src/**\n' > "$GD/.roadworthy/scope"
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$GD\",\"tool_input\":{\"file_path\":\"$GD/nope.md\"}}"
golden deny-envelope.json && ok "scope-lock denies in the golden envelope" || fail "scope-lock envelope: $OUT"
rm -f "$GD/.roadworthy/scope"

GTR='--tr'; GTR="${GTR}ailer"
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$GD\",\"tool_input\":{\"command\":\"git commit $GTR x -m m\"}}"
golden deny-envelope.json && ok "guard-commit denies in the golden envelope" || fail "guard-commit envelope: $OUT"

echo '{"topic":"g"}' > "$GD/.roadworthy/overnight"
run_hook overnight-guard "{\"tool_name\":\"Bash\",\"cwd\":\"$GD\",\"tool_input\":{\"command\":\"git push origin main\"}}"
golden deny-envelope.json && ok "overnight-guard denies in the golden envelope" || fail "overnight-guard envelope: $OUT"
rm -f "$GD/.roadworthy/overnight"

mkdir -p "$TMP/goldplans"
printf '# unreviewed\n' > "$TMP/goldplans/g.md"
CLAUDE_PLUGIN_OPTION_PLANS_DIR="$TMP/goldplans" run_hook plan-review-gate "{\"tool_name\":\"ExitPlanMode\",\"cwd\":\"$GD\",\"tool_input\":{}}"
golden deny-envelope.json && ok "plan-review-gate denies in the golden envelope" || fail "plan-review-gate envelope: $OUT"

# The fail-closed path returns the same envelope: a crash must be indistinguishable, to the
# harness, from a deliberate denial.
CLAUDE_PLUGIN_OPTION_PROTECTED_PATHS='x' run_hook protect-paths 'not json'
golden deny-envelope.json && ok "an internal error denies in the same golden envelope" || fail "crash envelope: $OUT"

# Context injection has its own contract and its own golden.
run_hook principles "{\"transcript_path\":\"$PROJ/s.jsonl\",\"cwd\":\"$GD\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"hi\"}"
golden context-envelope.json && ok "principles injects in the golden envelope" || fail "principles envelope: $OUT"

# And the golden has to be able to say no: a shape that is almost right must be rejected.
OUT='{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny"}}'
! golden deny-envelope.json && { ok "a denial missing the reason is rejected by the golden"; why; } || fail "golden accepted an envelope with no reason"
OUT='{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "no prefix"}}'
! golden deny-envelope.json && { ok "a reason that does not name Roadworthy is rejected"; why; } || fail "golden accepted an unattributed reason"
OUT='garbage "permissionDecision": "deny" garbage'
! golden deny-envelope.json && { ok "output that is not JSON is rejected (the old grep accepted it)"; why; } || fail "golden accepted non-JSON"

rw_end
