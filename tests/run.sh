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
for f in hooks/lib.sh hooks/principles hooks/protect-paths hooks/scope-lock hooks/guard-commit hooks/plan-review-gate skills/*/scripts/*.sh tests/run.sh; do
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

# ── plan template: risk band ────────────────────────────────────────────────
section "plan template"
grep -q '## Risk band' skills/plan/templates/plan.md && [ "$(grep -o -E '\*\*(protected|critical|standard|minimal)\*\*' skills/plan/templates/plan.md | sort -u | wc -l | tr -d ' ')" = "4" ] && ok "risk band with the four bands" || fail "risk band missing"

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
