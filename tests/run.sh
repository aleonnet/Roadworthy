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
for f in hooks/lib.sh hooks/principles hooks/protect-paths hooks/scope-lock hooks/guard-commit hooks/plan-review-gate hooks/overnight-guard skills/*/scripts/*.sh tests/run.sh; do
  bash -n "$f" && ok "bash -n $f" || fail "bash -n $f"
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning -x hooks/lib.sh hooks/principles hooks/protect-paths hooks/scope-lock hooks/guard-commit hooks/plan-review-gate hooks/overnight-guard skills/*/scripts/*.sh tests/run.sh \
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
[ "$n_general" = "13" ] && ok "13 bundled principles injected" || fail "bundled principles: $n_general"
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

# ── crash policy: guards fail closed, context injection fails open ──────────
section "crash policy"
CLAUDE_PLUGIN_OPTION_PROTECTED_PATHS='lib/**' run_hook protect-paths 'not json'
denied && [ "$RC" -eq 0 ] && ok "guard with invalid stdin → DENY (fails closed)" || fail "guard crash not denied (rc=$RC out=$OUT)"
run_hook guard-commit ''
denied && ok "guard with empty stdin → DENY" || fail "guard empty stdin not denied"
run_hook principles 'not json'
[ "$RC" -eq 1 ] && [ -z "$OUT" ] && ok "context hook with invalid stdin → exit 1 notice (fails open, never 2)" || fail "principles crash rc=$RC"
RW_ON_CRASH_TEST="$(RW_HOOK=x bash -c 'source hooks/lib.sh; rw_crash test' 2>&1 || true)"
printf '%s' "$RW_ON_CRASH_TEST" | grep -q 'no crash policy' && ok "hook without declared policy is itself an error" || fail "missing policy not detected"

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
G2="$TMP/git2"; mkdir -p "$G2"; git -C "$G2" init -q; git -C "$G2" config user.email t@t; git -C "$G2" config user.name t
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$TMP\",\"tool_input\":{\"command\":\"cd $G2 && git commit -m m\"}}"
denied && ok "leading cd: empty staging in the target repo denied" || fail "cd-prefixed commit judged by the wrong directory"
echo y > "$G2/g"; git -C "$G2" add g
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$TMP\",\"tool_input\":{\"command\":\"cd $G2 && git commit -m m\"}}"
! denied && ok "leading cd: staged change in the target repo allowed" || fail "cd-prefixed commit with staging denied"
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$TMP\",\"tool_input\":{\"command\":\"git -C $G2 commit -m m\"}}"
! denied && ok "git -C: judged by the named repo" || fail "git -C judged by cwd"
git -C "$G2" commit -q -m g
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$G2\",\"tool_input\":{\"command\":\"git add -A && git commit -m m\"}}"
! denied && ok "staging on the same line is left to git" || fail "add && commit denied before the add ran"
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
printf '#!/usr/bin/env bash\necho "always red"; exit 1\n' > "$T/red.sh"; chmod +x "$T/red.sh"
! bash skills/refute/scripts/refute.sh --file "$T/config.txt" --sed 's/42/43/' --expect 'always red' -- "$T/red.sh" >/dev/null 2>&1 \
  && ok "red on the clean file too is rejected (no green-on-clean)" || fail "always-red check accepted"

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
printf 'status: accepted\nplan: 2026-01-01-0900-first.md\nVERDICT: APPROVED\n' > "$D/2026-01-01-0900-first.review.md"
bash skills/document/scripts/docs-check.sh "$D" >/dev/null && ok "review companion (.review.md) next to the plan passes" || fail "review companion rejected"
printf 'status: accepted\n' > "$D/2026-01-01-0900-first.notes.md"
! bash skills/document/scripts/docs-check.sh "$D" >/dev/null 2>&1 && ok "other dotted suffix still fails" || fail "dotted suffix passed"
rm "$D/2026-01-01-0900-first.notes.md"
printf 'status: superseded by 2026-09-09-0000-nope.md\n' > "$D/2026-01-04-1200-dangling.md"
! bash skills/document/scripts/docs-check.sh "$D" >/dev/null 2>&1 && ok "dangling superseded-by fails" || fail "dangling passed"
rm "$D/2026-01-04-dangling.md" 2>/dev/null || rm "$D/2026-01-04-1200-dangling.md"
printf 'status: accepted\n[x](missing.md)\n' > "$D/2026-01-05-1300-broken-link.md"
! bash skills/document/scripts/docs-check.sh "$D" >/dev/null 2>&1 && ok "broken relative link fails" || fail "broken link passed"

# ── protect-paths: project file ──────────────────────────────────────────────
section "protect-paths (.roadworthy/protected)"
PP="$TMP/pp"; mkdir -p "$PP/.roadworthy" "$PP/lib/auth"; printf '# protected\nlib/auth/**\n' > "$PP/.roadworthy/protected"
run_hook protect-paths "{\"tool_name\":\"Edit\",\"cwd\":\"$PP\",\"tool_input\":{\"file_path\":\"$PP/lib/auth/x.py\"}}"
denied && ok "project file glob denied without any user option" || fail "project protected file ignored"
run_hook protect-paths "{\"tool_name\":\"Edit\",\"cwd\":\"$PP\",\"tool_input\":{\"file_path\":\"$PP/lib/other.py\"}}"
! denied && ok "outside project globs allowed" || fail "outside project glob denied"

# ── plan-review-gate: review_suffix and Portuguese fields ───────────────────
section "plan-review-gate (review_suffix)"
export CLAUDE_PLUGIN_OPTION_PLANS_DIR="$P"
printf '# plano\n' > "$P/outro.md"; sha="$(shasum -a 256 "$P/outro.md" | cut -d' ' -f1)"
printf 'plano: outro.md\nplano-sha256: %s\nVEREDITO: APROVADO\n' "$sha" > "$P/outro.banca.md"
CLAUDE_PLUGIN_OPTION_REVIEW_SUFFIX=.banca.md run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
! denied && ok "custom suffix + Portuguese fields accepted" || fail "custom suffix rejected: $OUT"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && ok "default suffix ignores the .banca.md review" || fail "default suffix accepted wrong file"
unset CLAUDE_PLUGIN_OPTION_PLANS_DIR

# ── docs-init: idempotent tree by role ──────────────────────────────────────
section "docs-init.sh"
DI="$TMP/di"; mkdir -p "$DI"
bash skills/document/scripts/docs-init.sh "$DI" > "$TMP/di1.log" && ok "first run creates the tree" || fail "docs-init first run"
grep -q 'created  docs/decisions/' "$TMP/di1.log" && [ -f "$DI/docs/README.md" ] && [ -f "$DI/docs/plans/done/README.md" ] && ok "map, roles and done index created" || fail "tree incomplete"
snap="$(cd "$DI" && find . -type f -exec shasum -a 256 {} + | sort)"
bash skills/document/scripts/docs-init.sh "$DI" > "$TMP/di2.log"
[ "$snap" = "$(cd "$DI" && find . -type f -exec shasum -a 256 {} + | sort)" ] && ! grep -q 'created' "$TMP/di2.log" && ok "second run changes nothing and reports 'exists'" || fail "docs-init not idempotent"

# ── docs-check v2: role-aware rules ─────────────────────────────────────────
section "docs-check.sh (roles)"
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

# ── resume-pick: newest by NAME, never by mtime ─────────────────────────────
section "resume-pick.sh"
touch "$DI/docs/plans/2026-01-01-0900-handoff-a.md"   # older handoff, newer mtime
[ "$(bash skills/resume/scripts/resume-pick.sh "$DI")" = "$DI/docs/plans/2026-01-02-0900-handoff-b.md" ] && ok "picks the newest by name despite mtime" || fail "resume-pick chose by mtime"
printf 'status: superseded by 2026-01-01-0900-handoff-a.md\n' > "$DI/docs/plans/2026-01-02-0900-handoff-b.md"
! bash skills/resume/scripts/resume-pick.sh "$DI" >/dev/null 2>&1 && ok "superseded-by pointing at something older fails" || fail "backward pointer accepted"
printf 'status: accepted\n' > "$DI/docs/plans/2026-01-02-0900-handoff-b.md"

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

# ── tree-fingerprint: content, not commits ──────────────────────────────────
section "tree-fingerprint.sh (content)"
read -r _ t1 _ <<< "$(bash skills/close/scripts/tree-fingerprint.sh "$CF")"
git -C "$CF" commit -q --allow-empty -m "no content change"
read -r _ t2 _ <<< "$(bash skills/close/scripts/tree-fingerprint.sh "$CF")"
[ "$t1" = "$t2" ] && ok "new commit with identical content keeps the fingerprint" || fail "fingerprint changed without content change"
echo x >> "$CF/docs/README.md"
read -r _ t3 s3 <<< "$(bash skills/close/scripts/tree-fingerprint.sh "$CF")"
[ "$t1" != "$t3" ] && [ "$s3" = "dirty" ] && ok "one byte changes it and the tree is dirty" || fail "content change not detected"
git -C "$CF" checkout -q -- docs/README.md

# ── close.sh: gates, evidence, FRESH/STALE, states ──────────────────────────
section "close.sh"
export ROADWORTHY_DATA="$TMP/rwdata"
printf 'true\n' > "$CF/.roadworthy/gates"; printf 'docs/**\n' > "$CF/.roadworthy/scope"
rc=0; (cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh") > "$TMP/close1.log" 2>&1 || rc=$?
[ $rc -eq 1 ] && grep -q 'dirty' "$TMP/close1.log" && ok "dirty tree refused (gates untracked)" || fail "dirty tree accepted"
git -C "$CF" add -A; git -C "$CF" commit -q -m gates
(cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh") > "$TMP/close2.log" 2>&1 && ok "green gate → passed" || { fail "green gate failed"; cat "$TMP/close2.log"; }
[ ! -f "$CF/.roadworthy/scope" ] && [ "$(cat "$ROADWORTHY_DATA/state")" = "passed" ] && ok "scope released, state passed" || fail "scope/state after pass"
(cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh" --check) | grep -q 'FRESH     true' && ok "--check reports FRESH on the same tree" || fail "not FRESH"
echo y >> "$CF/docs/README.md"
{ (cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh" --check) || true; } | grep -q 'STALE' && ok "--check reports STALE after an edit" || fail "not STALE after edit"
git -C "$CF" checkout -q -- docs/README.md
printf 'false\n' > "$CF/.roadworthy/gates"; printf 'docs/**\n' > "$CF/.roadworthy/scope"; git -C "$CF" add -A; git -C "$CF" commit -q -m red
! (cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh") >/dev/null 2>&1 && [ -f "$CF/.roadworthy/scope" ] && [ "$(cat "$ROADWORTHY_DATA/state")" = "gaps_found" ] && ok "red gate → gaps_found, scope kept" || fail "red gate handling"
(cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh" --needs-human "device bench") >/dev/null && [ "$(cat "$ROADWORTHY_DATA/state")" = "needs_human" ] && ok "--needs-human records the state" || fail "needs_human"
unset ROADWORTHY_DATA

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

# ── refute-ledger ───────────────────────────────────────────────────────────
section "refute-ledger.sh"
RL="$TMP/rl"; mkdir -p "$RL"
printf '// FENCE: x\n// checks y\n// refuted 2026-01-01: injected z → Actual: red\n' > "$RL/a_test.dart"
printf '// FENCE: without record\n// checks y\n' > "$RL/b_test.dart"
printf '// plain test\n' > "$RL/c_test.dart"
! bash skills/refute/scripts/refute-ledger.sh "$RL" >/dev/null 2>&1 && ok "fence without a refutation record fails" || fail "unrecorded fence passed"
printf '%s\n' "$RL/b_test.dart" > "$RL/legacy.txt"
bash skills/refute/scripts/refute-ledger.sh "$RL" --legacy "$RL/legacy.txt" | grep -q '2 fence(s), 1 legacy, 0 without' && ok "legacy list tolerates declared debt and counts it" || fail "legacy handling"
printf '// FENCE: spike\n// DUMP — not a guarantee\n' > "$RL/d_test.dart"
! bash skills/refute/scripts/refute-ledger.sh "$RL" --legacy "$RL/legacy.txt" >/dev/null 2>&1 && ok "diagnostic file counted as fence without --exclude" || fail "diagnostic ignored without --exclude"
bash skills/refute/scripts/refute-ledger.sh "$RL" --legacy "$RL/legacy.txt" --exclude 'DUMP|SPIKE' | grep -q '2 fence(s), 1 legacy, 0 without' && ok "--exclude skips self-declared diagnostics" || fail "--exclude handling"

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

# ── protect-paths: overnight freeze ──────────────────────────────────────────
section "protect-paths (overnight freeze)"
run_hook protect-paths "{\"tool_name\":\"Edit\",\"cwd\":\"$ON\",\"tool_input\":{\"file_path\":\"$ON/pubspec.yaml\"}}"
denied && printf '%s' "$OUT" | grep -q 'frozen for the night' && ok "frozen file denied with the marker" || fail "frozen file passed"
run_hook protect-paths "{\"tool_name\":\"Edit\",\"cwd\":\"$ON\",\"tool_input\":{\"file_path\":\"$ON/lib/a.dart\"}}"
! denied && ok "file outside the freeze list allowed" || fail "unfrozen file denied"
run_hook protect-paths "{\"tool_name\":\"Edit\",\"cwd\":\"$SUB\",\"tool_input\":{\"file_path\":\"$ON/pubspec.yaml\"}}"
denied && ok "frozen file denied from a subdirectory cwd (root = git top-level)" || fail "freeze fails open from a subdirectory"
rm -f "$ON/.roadworthy/overnight"
run_hook protect-paths "{\"tool_name\":\"Edit\",\"cwd\":\"$ON\",\"tool_input\":{\"file_path\":\"$ON/pubspec.yaml\"}}"
! denied && ok "without the marker the freeze list is inert" || fail "freeze applied without the marker"

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
printf 'plan: 2026-01-02-0100-night.md\nplan-sha256: 0000\nVERDICT: APPROVED\n' > "$OV/docs/plans/2026-01-02-0100-night.review.md"
git -C "$OV" add -A; git -C "$OV" commit -q -m stale
! (cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0100-night.md night) >/dev/null 2>"$TMP/ov2b" && grep -q 'SHA-256' "$TMP/ov2b" && ok "start refused on a review bound to another hash" || fail "start on stale review: $(cat "$TMP/ov2b")"
printf 'plan: 2026-01-02-0100-night.md\nplan-sha256: %s\nVERDICT: APPROVED\n' "$sha" > "$OV/docs/plans/2026-01-02-0100-night.review.md"
! (cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0100-night.md night) >/dev/null 2>"$TMP/ov3" && grep -q 'dirty' "$TMP/ov3" && ok "start refused on a dirty tree (approved review not committed)" || fail "start on dirty tree: $(cat "$TMP/ov3")"
git -C "$OV" add -A; git -C "$OV" commit -q -m review
printf '# plan without policy\n' > "$OV/docs/plans/2026-01-02-0200-nopolicy.md"
sha2="$(shasum -a 256 "$OV/docs/plans/2026-01-02-0200-nopolicy.md" | cut -d' ' -f1)"
printf 'plan: x\nplan-sha256: %s\nVERDICT: APPROVED\n' "$sha2" > "$OV/docs/plans/2026-01-02-0200-nopolicy.review.md"
git -C "$OV" add -A; git -C "$OV" commit -q -m nopolicy
! (cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0200-nopolicy.md night) >/dev/null 2>"$TMP/ov4" && grep -q 'Overnight policy' "$TMP/ov4" && ok "start refused on a plan without the Overnight policy section" || fail "start without policy section"
t0="$(python3 -c 'import time; print(int(time.time()*1000))')"
diary="$(cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0100-night.md night | tail -1)"
t1="$(python3 -c 'import time; print(int(time.time()*1000))')"
[ -f "$OV/.roadworthy/overnight" ] && [ -f "$OV/$diary" ] && ok "start writes the marker and the diary ($diary)" || fail "start did not write marker/diary"
ms="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["started_ms"])' "$OV/.roadworthy/overnight")"
[ "$ms" -ge "$t0" ] && [ "$ms" -le "$t1" ] && ok "started_ms was measured by the script (within the test's clock window)" || fail "started_ms outside window: $t0 ≤ $ms ≤ $t1"
! (cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0100-night.md night) >/dev/null 2>"$TMP/ov5" && grep -q 'already on' "$TMP/ov5" && ok "start refused while the marker exists" || fail "double start accepted"
! (cd "$OV" && bash "$S/overnight-entry.sh" --phase F1 --decision d --reason r) >/dev/null 2>"$TMP/ov6" && grep -q -- '--source' "$TMP/ov6" && ok "entry refused without a source" || fail "entry without source accepted"
(cd "$OV" && bash "$S/overnight-entry.sh" --phase F1 --decision "use X" --reason "spec says so" --source "RFC 0000 §1" --ratify) >/dev/null && grep -q -E '^- `[0-9]{13}` · [0-9T:Z-]+ · \*\*F1\*\* · use X · reason: spec says so · source: RFC 0000 §1 · ratify in the morning$' "$OV/$diary" && ok "entry carries epoch ms + ISO taken by the script, under Decisions" || fail "entry format: $(grep 'use X' "$OV/$diary")"
(cd "$OV" && bash "$S/overnight-entry.sh" --blocker "pricing is the user's") >/dev/null && python3 - "$OV/$diary" <<'PY' && ok "blocker lands under its own section" || fail "blocker section"
import sys; t=open(sys.argv[1]).read(); i=t.index("## Blockers for the morning"); j=t.index("## Delivery"); sys.exit(0 if "pricing is the user's" in t[i:j] else 1)
PY
(cd "$OV" && bash "$S/overnight-entry.sh" --phase-done F1 --sha abc1234 --gates "suite green") >/dev/null && grep -q '^| F1 | `abc1234` | suite green |' "$OV/$diary" && [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["phase"])' "$OV/.roadworthy/overnight")" = "F1" ] && ok "phase ledger row; marker phase follows" || fail "phase ledger row / marker phase"
export ROADWORTHY_DATA="$TMP/ovdata"
! (cd "$OV" && bash "$S/overnight-close.sh") >/dev/null 2>"$TMP/ov7" && grep -q 'dirty' "$TMP/ov7" && ok "close refused on a dirty tree (the diary is uncommitted)" || fail "close on dirty tree"
git -C "$OV" add -A; git -C "$OV" commit -q -m diary
! (cd "$OV" && bash "$S/overnight-close.sh") >/dev/null 2>"$TMP/ov8" && grep -q -E 'STALE|MISSING' "$TMP/ov8" && [ -f "$OV/.roadworthy/overnight" ] && ok "close refused while a gate is MISSING; marker kept" || fail "close without evidence accepted"
handoff="$(cd "$OV" && bash "$S/overnight-close.sh" --run | tail -1)"
[ -f "$OV/$handoff" ] && [ ! -f "$OV/.roadworthy/overnight" ] && grep -q "pricing is the user's" "$OV/$handoff" && grep -q '| ov | ' "$OV/$handoff" && ok "close with FRESH gates writes the hand-off with the blockers and removes the marker" || fail "close --run: $handoff"
unset ROADWORTHY_DATA

# ── plan template: risk band ────────────────────────────────────────────────
# ── rw-metrics: KPIs from a synthetic run ───────────────────────────────────
section "rw-metrics"
if python3 -m pytest --version >/dev/null 2>&1; then
  RM="$TMP/rm"; mkdir -p "$RM/run/out" "$RM/run/sealed/home/cwd"
  W="$RM/run/sealed/home/cwd"
  (cd "$W" && git init -q && mkdir -p app tests && printf 'def f():\n    return 1\n' > app/a.py && : > app/__init__.py \
    && printf 'from app.a import f\n\ndef test_f():\n    assert f() == 2\n' > tests/test_a.py \
    && printf 'def test_ok():\n    assert True\n' > tests/test_b.py \
    && printf 'app/a.py\n' > SCOPE.txt && printf 'tests/test_a.py::test_f\n' > TARGET_TESTS.txt \
    && git -c user.name=t -c user.email=t@e add -A && git -c user.name=t -c user.email=t@e commit -q -m base \
    && printf 'def f():\n    return 2\n' > app/a.py && printf 'def test_ok():\n    assert False\n' > tests/test_b.py && printf 'x\n' > stray.txt)
  printf '%s\n' '{"type":"result","num_turns":4,"duration_ms":9000,"result":"done\nSTATUS: passed","permission_denials":[{"tool_name":"Edit"}],"modelUsage":{"m":{"inputTokens":100,"outputTokens":50,"cacheReadInputTokens":7}}}' > "$RM/run/out/trace.jsonl"
  printf '{"cases":[{"name":"c","arms":{"with":[{"score":1,"costUsd":0.1,"turns":4,"durationSeconds":9,"tracePath":"%s"}]}}]}' "$RM/run/out/trace.jsonl" > "$RM/r.json"
  out="$(python3 bin/rw-metrics t="$RM/r.json" 2>&1)"
  echo "$out" | grep -q '| t | c | with | 1 | 1.0 | 1/1 | 1 | 2 | 1 | 1 | 1 | 150.0 | 7.0 | 4.0 | 9.0 | 0.1 |' && ok "K1 pass, K2 one regression, K3 two files out of scope, K4 false success, K5 one denial, K6/K7 from the trace" || { fail "rw-metrics table differs"; echo "$out" | head -5; }
else
  echo "  [SKIP] pytest not installed"
fi

section "plan template"
grep -q '## Risk band' skills/plan/templates/plan.md && [ "$(grep -o -E '\*\*(protected|critical|standard|minimal)\*\*' skills/plan/templates/plan.md | sort -u | wc -l | tr -d ' ')" = "4" ] && ok "risk band with the four bands" || fail "risk band missing"
grep -q '^## Overnight policy' skills/plan/templates/plan.md && grep -q 'Reserved for the user' skills/plan/templates/plan.md && ok "overnight policy section with the two lists" || fail "overnight policy section missing"

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
