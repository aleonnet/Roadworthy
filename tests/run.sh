#!/usr/bin/env bash
# The quality gate for Roadworthy itself. Local and CI run exactly this.
#
# Every hook is exercised with real stdin JSON, in both directions: it must deny
# what it claims to deny and pass what it claims to pass. Every script is
# refuted once. The manifest is validated with the official CLI when present.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export CLAUDE_PLUGIN_ROOT="$ROOT"

FAIL=0
ok()   { printf '  [OK]   %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
section() { printf '\n== %s\n' "$1"; }

# run_hook <name> <json> → sets OUT (stdout), ERR (stderr), RC
run_hook() {
  local name="$1" json="$2"
  set +e
  OUT="$(printf '%s' "$json" | bash "$ROOT/hooks/run-hook.cmd" "$name" 2>"$TMP/err")"
  RC=$?
  set -e
  ERR="$(cat "$TMP/err")"
}
denied()  { printf '%s' "$OUT" | grep -q '"permissionDecision": "deny"'; }
context() { printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
HOME_SANDBOX="$TMP/home"; mkdir -p "$HOME_SANDBOX/.claude/plans"

# ── shell hygiene ────────────────────────────────────────────────────────────
section "shell syntax"
for f in hooks/lib.sh hooks/principles hooks/protect-paths hooks/scope-lock hooks/guard-commit hooks/plan-review-gate skills/refute/scripts/refute.sh skills/close/scripts/tree-fingerprint.sh skills/document/scripts/docs-check.sh tests/run.sh; do
  bash -n "$f" && ok "bash -n $f" || fail "bash -n $f"
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning -x hooks/lib.sh hooks/principles hooks/protect-paths hooks/scope-lock hooks/guard-commit hooks/plan-review-gate skills/*/scripts/*.sh tests/run.sh \
    && ok "shellcheck (warning)" || fail "shellcheck"
else
  echo "  [SKIP] shellcheck not installed"
fi
python3 -c 'import json; json.load(open(".claude-plugin/plugin.json")); json.load(open(".claude-plugin/marketplace.json")); json.load(open("hooks/hooks.json"))' \
  && ok "manifests are valid JSON" || fail "manifest JSON"

# ── principles ───────────────────────────────────────────────────────────────
section "principles (UserPromptSubmit)"
PROJ="$HOME_SANDBOX/.claude/projects/-tmp-proj"; mkdir -p "$PROJ/memory"
printf '# index\n1. Project rule one → [detail](feedback_one.md)\n- not a rule\n2. Project rule two\n' > "$PROJ/memory/MEMORY.md"
: > "$PROJ/memory/feedback_one.md"
run_hook principles "{\"transcript_path\":\"$PROJ/s.jsonl\",\"cwd\":\"/tmp\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"hi\"}"
[ "$RC" -eq 0 ] && [ -z "$ERR" ] && ok "exit 0, silent stderr" || fail "principles rc=$RC err=$ERR"
n_general="$(context | awk '/^ROADWORTHY PRINCIPLES/{s=1;next} /^PROJECT RULES/{s=0} s' | grep -c -E '^[0-9]+[a-z]*\. ' || true)"
n_project="$(context | awk '/^PROJECT RULES/{s=1;next} s' | grep -c -E '^[0-9]+[a-z]*\. ' || true)"
[ "$n_general" = "12" ] && ok "12 bundled principles injected" || fail "bundled principles: $n_general"
[ "$n_project" = "2" ] && ok "2 project rules injected, prose skipped" || fail "project rules: $n_project"
context | grep -q "](${PROJ}/memory/feedback_one.md)" && ok "relative link rewritten to absolute" || fail "link rewrite"
run_hook principles "{\"transcript_path\":\"$HOME_SANDBOX/.claude/projects/-none/s.jsonl\"}"
[ "$(context | grep -c '^PROJECT RULES')" = "0" ] && ok "no memory dir → general layer only" || fail "unexpected project layer"
CLAUDE_PLUGIN_OPTION_PROJECT_RULES=false run_hook principles "{\"transcript_path\":\"$PROJ/s.jsonl\"}"
[ "$(context | grep -c '^PROJECT RULES')" = "0" ] && ok "project_rules=false honoured" || fail "project_rules=false"
printf '1. Only mine\n' > "$TMP/mine.md"
CLAUDE_PLUGIN_OPTION_PRINCIPLES_FILE="$TMP/mine.md" run_hook principles '{"transcript_path":""}'
[ "$(context | grep -c '^1\. Only mine')" = "1" ] && ok "principles_file override" || fail "principles_file override"
CLAUDE_PLUGIN_OPTION_PRINCIPLES_FILE="$TMP/missing.md" run_hook principles '{"transcript_path":""}'
[ "$RC" -eq 1 ] && [ -z "$OUT" ] && [ -n "$ERR" ] && ok "missing principles file → exit 1 + notice, never 2" || fail "missing file rc=$RC"
run_hook principles 'not json'
[ "$RC" -eq 1 ] && [ -n "$ERR" ] && ok "malformed stdin → exit 1 + notice" || fail "malformed stdin rc=$RC"

# ── protect-paths ────────────────────────────────────────────────────────────
section "protect-paths"
E='{"tool_name":"Edit","cwd":"/repo","tool_input":{"file_path":"/repo/lib/ble/manager.dart"}}'
CLAUDE_PLUGIN_OPTION_PROTECTED_PATHS='lib/ble/**,**/permissions.dart' run_hook protect-paths "$E"
denied && ok "edit inside protected glob denied" || fail "protected glob not denied"
CLAUDE_PLUGIN_OPTION_PROTECTED_PATHS='lib/ble/**' run_hook protect-paths '{"tool_name":"Edit","cwd":"/repo","tool_input":{"file_path":"/repo/lib/ui/home.dart"}}'
! denied && [ "$RC" -eq 0 ] && ok "edit outside protected glob allowed" || fail "outside glob wrongly denied"
CLAUDE_PLUGIN_OPTION_PROTECTED_PATHS='**/permissions.dart' run_hook protect-paths '{"tool_name":"Write","cwd":"/repo","tool_input":{"file_path":"/repo/a/b/permissions.dart"}}'
denied && ok "** matches any depth" || fail "** depth"
run_hook protect-paths "$E"
! denied && ok "empty option → guard inactive" || fail "empty option denied"

# ── scope-lock ───────────────────────────────────────────────────────────────
section "scope-lock"
REPO="$TMP/repo"; mkdir -p "$REPO/.roadworthy" "$REPO/src" "$REPO/docs"
printf '# scope\nsrc/**\n' > "$REPO/.roadworthy/scope"
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$REPO/docs/readme.md\"}}"
denied && ok "edit outside scope denied" || fail "outside scope not denied"
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$REPO/src/a.dart\"}}"
! denied && ok "edit inside scope allowed" || fail "inside scope denied"
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$REPO/.roadworthy/scope\"}}"
! denied && ok "scope file itself editable" || fail "scope file denied"
rm "$REPO/.roadworthy/scope"
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$REPO/docs/readme.md\"}}"
! denied && ok "no scope file → lock inactive" || fail "lock active without scope file"

# ── guard-commit ─────────────────────────────────────────────────────────────
section "guard-commit"
G="$TMP/git"; mkdir -p "$G"; git -C "$G" init -q; git -C "$G" config user.email t@t; git -C "$G" config user.name t
TR='--tr'; TR="${TR}ailer"
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$G\",\"tool_input\":{\"command\":\"git commit $TR x -m m\"}}"
denied && ok "forbidden flag denied" || fail "forbidden flag passed"
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$G\",\"tool_input\":{\"command\":\"git commit -m m\"}}"
denied && ok "empty staging denied" || fail "empty staging passed"
echo x > "$G/f"; git -C "$G" add f
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$G\",\"tool_input\":{\"command\":\"git commit -m m\"}}"
! denied && ok "staged change allowed" || fail "staged change denied"
CLAUDE_PLUGIN_OPTION_BLOCK_EMPTY_COMMITS=false run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$TMP\",\"tool_input\":{\"command\":\"git commit -m m\"}}"
! denied && ok "block_empty_commits=false honoured" || fail "block_empty_commits=false"
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$G\",\"tool_input\":{\"command\":\"echo hello\"}}"
! denied && [ "$RC" -eq 0 ] && ok "non-commit command untouched" || fail "non-commit denied"

# ── plan-review-gate ─────────────────────────────────────────────────────────
section "plan-review-gate"
P="$HOME_SANDBOX/.claude/plans"; printf '# plan\n' > "$P/my-plan.md"
export CLAUDE_PLUGIN_OPTION_PLANS_DIR="$P"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && ok "no review → denied" || fail "no review passed"
sha="$(shasum -a 256 "$P/my-plan.md" | cut -d' ' -f1)"
printf 'plan: my-plan.md\nplan-sha256: %s\nVERDICT: APPROVED\n' "$sha" > "$P/my-plan.review.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
! denied && ok "approved review bound to sha → allowed" || fail "approved review denied"
printf '# plan edited\n' > "$P/my-plan.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && ok "editing the plan invalidates the review" || fail "stale review accepted"
sha="$(shasum -a 256 "$P/my-plan.md" | cut -d' ' -f1)"
printf 'plan: my-plan.md\nplan-sha256: %s\nVERDICT: REJECTED\n' "$sha" > "$P/my-plan.review.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && ok "rejected review → denied" || fail "rejected review passed"
printf 'plan: ../x.md\nplan-sha256: %s\nVERDICT: APPROVED\n' "$sha" > "$P/evil.review.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && ok "review with '/' in plan name refused" || fail "path traversal accepted"
rm "$P/evil.review.md"
CLAUDE_PLUGIN_OPTION_PLAN_REVIEW_REQUIRED=false run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
! denied && ok "plan_review_required=false honoured" || fail "plan_review_required=false"
unset CLAUDE_PLUGIN_OPTION_PLANS_DIR

# ── refute.sh (refuted with a toy check) ─────────────────────────────────────
section "refute.sh"
T="$TMP/toy"; mkdir -p "$T"; printf 'answer=42\n' > "$T/config.txt"
cat > "$T/check.sh" <<'EOF'
#!/usr/bin/env bash
grep -q '^answer=42$' "$(dirname "$0")/config.txt" || { echo "config: answer is not 42"; exit 1; }
EOF
chmod +x "$T/check.sh"
before="$(shasum -a 256 "$T/config.txt" | cut -d' ' -f1)"
bash skills/refute/scripts/refute.sh --file "$T/config.txt" --sed 's/42/43/' --expect 'answer is not 42' -- "$T/check.sh" >/dev/null \
  && ok "check goes red for the intended reason; file restored" || fail "refute happy path"
[ "$(shasum -a 256 "$T/config.txt" | cut -d' ' -f1)" = "$before" ] && ok "hash identical after restore" || fail "hash differs after restore"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/green.sh"; chmod +x "$T/green.sh"
! bash skills/refute/scripts/refute.sh --file "$T/config.txt" --sed 's/42/43/' --expect 'x' -- "$T/green.sh" >/dev/null 2>&1 \
  && ok "a check that stays green is reported as a failed refutation" || fail "green check accepted"
! bash skills/refute/scripts/refute.sh --file "$T/config.txt" --sed 's/42/43/' --expect 'some other reason' -- "$T/check.sh" >/dev/null 2>&1 \
  && ok "red for the wrong reason is rejected" || fail "wrong reason accepted"
! bash skills/refute/scripts/refute.sh --file "$T/config.txt" --sed 's/nomatch/x/' --expect 'x' -- "$T/check.sh" >/dev/null 2>&1 \
  && ok "injection that changes nothing is rejected" || fail "no-op injection accepted"

# ── tree-fingerprint ─────────────────────────────────────────────────────────
section "tree-fingerprint.sh"
fp1="$(bash skills/close/scripts/tree-fingerprint.sh "$G")"
echo y > "$G/f"
fp2="$(bash skills/close/scripts/tree-fingerprint.sh "$G")"
[ "$fp1" != "$fp2" ] && ok "fingerprint changes with the tree" || fail "fingerprint unchanged"
printf '%s' "$fp2" | grep -q ' dirty$' && ok "dirty tree reported" || fail "dirty not reported"

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
printf 'status: superseded by 2026-09-09-0000-nope.md\n' > "$D/2026-01-04-1200-dangling.md"
! bash skills/document/scripts/docs-check.sh "$D" >/dev/null 2>&1 && ok "dangling superseded-by fails" || fail "dangling passed"
rm "$D/2026-01-04-dangling.md" 2>/dev/null || rm "$D/2026-01-04-1200-dangling.md"
printf 'status: accepted\n[x](missing.md)\n' > "$D/2026-01-05-1300-broken-link.md"
! bash skills/document/scripts/docs-check.sh "$D" >/dev/null 2>&1 && ok "broken relative link fails" || fail "broken link passed"

# ── privacy: the plugin must carry no personal data ──────────────────────────
section "privacy scan"
if grep -r -n -E '/Users/[a-z]+|/home/[a-z]+' --include='*' . --exclude-dir=.git --exclude-dir=tests | grep -v 'tests/' >/dev/null; then
  fail "absolute home path found in plugin sources"
else ok "no absolute home paths"; fi

# ── official validation ──────────────────────────────────────────────────────
section "claude plugin validate"
if command -v claude >/dev/null 2>&1; then
  claude plugin validate . --strict >/dev/null 2>"$TMP/v" && ok "claude plugin validate --strict" || { fail "claude plugin validate"; cat "$TMP/v"; }
else
  echo "  [SKIP] claude CLI not installed"
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then echo "RESULT: gate clean"; else echo "RESULT: $FAIL failure(s)"; exit 1; fi
