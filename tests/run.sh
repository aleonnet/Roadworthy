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
# A TRAP THIS SUITE SET FOR ITSELF, measured 2026-09-13: with `set -o pipefail` above, a
# pipeline `<live command> | grep -q PATTERN` fails whenever the producer writes anything AFTER
# the match -- grep -q exits at once, the producer takes SIGPIPE (141), and pipefail turns that
# into a red assertion about something that actually worked. Adding one warning line to
# close.sh broke an unrelated FRESH assertion this way. Rule: capture the output into a
# variable first, then match it. Only match a live pipeline when the pattern is on its LAST
# line, where there is nothing left to write.
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
# A denial is judged by its SHAPE, not by a substring. `grep -q '"permissionDecision": "deny"'`
# accepted any line that merely contained those characters -- including output that is not JSON
# at all -- and rejected valid JSON formatted with different spacing. Both directions measured.
denied()  { printf '%s' "$OUT" | python3 -c 'import json,sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(1)
o = d.get("hookSpecificOutput") or {}
sys.exit(0 if o.get("permissionDecision") == "deny" else 1)'; }
# And once per guard, the WHOLE envelope is compared against the golden, key for key.
golden()  { printf '%s' "$OUT" | python3 "$ROOT/tests/goldens/check.py" "$ROOT/tests/goldens/$1" 2>"$TMP/golden.err"; }
# why() prints the divergence the golden found, for the assertions that expect one.
why()     { sed "s/^/          /" "$TMP/golden.err"; }
context() { printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
HOME_SANDBOX="$TMP/home"; mkdir -p "$HOME_SANDBOX/.claude/plans"

# ── shell hygiene ────────────────────────────────────────────────────────────
section "shell syntax"
for f in hooks/lib.sh hooks/principles hooks/protect-paths hooks/scope-lock hooks/guard-commit hooks/plan-review-gate hooks/overnight-guard hooks/rite-gate hooks/stop-gate skills/*/scripts/*.sh tests/run.sh; do
  bash -n "$f" && ok "bash -n $f" || fail "bash -n $f"
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning -x hooks/lib.sh hooks/principles hooks/protect-paths hooks/scope-lock hooks/guard-commit hooks/plan-review-gate hooks/overnight-guard hooks/rite-gate hooks/stop-gate skills/*/scripts/*.sh tests/run.sh \
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
[ "$n_general" = "8" ] && ok "8 bundled principles injected (only rules with a mechanism behind them)" || fail "bundled principles: $n_general"
[ "$n_project" = "2" ] && ok "2 project rules injected, prose skipped" || fail "project rules: $n_project"
CTX="$(context)"; printf '%s' "$CTX" | grep -q "](${PROJ}/memory/feedback_one.md)" && ok "relative link rewritten to absolute" || fail "link rewrite"
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
# The principles file lives OUTSIDE every repository and is shared by every project, so nothing
# here can stop it being edited -- not protect-paths, which only builds a path inside the session
# directory, not the entry gate, which only denies inside a repository. What a mechanism CAN do is
# refuse to let the change pass unannounced, at every prompt, until the owner agrees to it.
PIND="$TMP/pindata"; PINF="$TMP/pinned-principles.md"; mkdir -p "$PIND"
printf '1. One.\n2. Two.\n' > "$PINF"
CLAUDE_PLUGIN_OPTION_PRINCIPLES_FILE="$PINF" ROADWORTHY_DATA="$PIND" run_hook principles '{"transcript_path":"","cwd":"/tmp"}'
CTX1="$(context)"
printf '%s' "$CTX1" | grep -q 'CHANGED SINCE' && fail "warned on the first sight of a file" || ok "the first sight of a principles file pins it, silently"
printf '1. One.\n2. Two, edited.\n' > "$PINF"
CLAUDE_PLUGIN_OPTION_PRINCIPLES_FILE="$PINF" ROADWORTHY_DATA="$PIND" run_hook principles '{"transcript_path":"","cwd":"/tmp"}'
CTX2="$(context)"
printf '%s' "$CTX2" | grep -q 'THE PRINCIPLES FILE CHANGED' && ok "an edit to the principles file is announced in the prompt" || fail "a silent edit to the principles file"
printf '%s' "$CTX2" | grep -q 'agreed:' && ok "and the notice names the digest and the date last agreed" || fail "the notice does not say what was agreed: $CTX2"
CLAUDE_PLUGIN_OPTION_PRINCIPLES_FILE="$PINF" ROADWORTHY_DATA="$PIND" run_hook principles '{"transcript_path":"","cwd":"/tmp"}'
printf '%s' "$(context)" | grep -q 'THE PRINCIPLES FILE CHANGED' && ok "and it repeats every prompt: it is not a one-off that scrolls away" || fail "the notice appeared once and vanished"
# A fence that keeps denying the same way becomes a line in the next prompt. An agent does not
# remember, but it reads -- this is the only kind of consequence that reaches the following turn.
DENR="$TMP/denyrepo"; DEND="$TMP/denydata"; mkdir -p "$DENR/.roadworthy" "$DEND"; git -C "$DENR" init -q
printf 'src/**\n' > "$DENR/.roadworthy/scope"
for i in 1 2; do
  ROADWORTHY_DATA="$DEND" run_hook scope-lock "{\"tool_name\":\"Edit\",\"session_id\":\"d1\",\"cwd\":\"$DENR\",\"tool_input\":{\"file_path\":\"$DENR/out$i.md\"}}"
done
ROADWORTHY_DATA="$DEND" run_hook principles "{\"transcript_path\":\"\",\"cwd\":\"$DENR\"}"
printf '%s' "$(context)" | grep -q 'HAS DENIED THE SAME WAY' && fail "two denials already counted as a pattern" || ok "two denials are not yet a pattern"
ROADWORTHY_DATA="$DEND" run_hook scope-lock "{\"tool_name\":\"Edit\",\"session_id\":\"d1\",\"cwd\":\"$DENR\",\"tool_input\":{\"file_path\":\"$DENR/out3.md\"}}"
ROADWORTHY_DATA="$DEND" run_hook principles "{\"transcript_path\":\"\",\"cwd\":\"$DENR\"}"
CTX3="$(context)"
printf '%s' "$CTX3" | grep -q 'HAS DENIED THE SAME WAY' && ok "the third denial by the same fence comes back as a line in the prompt" || fail "three denials did not become a rule"
printf '%s' "$CTX3" | grep -q 'scope-lock: 3 denials' && ok "and it names the fence and the count" || fail "the injected line does not name the fence: $CTX3"
# It must not be a numbered line: those are the principles, and the suite counts them.
n_after="$(printf '%s' "$CTX3" | awk '/^ROADWORTHY PRINCIPLES/{s=1;next} /^PROJECT RULES|^A FENCE/{s=0} s' | grep -c -E '^[0-9]+[a-z]*\. ' || true)"
[ "$n_after" = "8" ] && ok "the injected line is not a numbered principle (still eight)" || fail "the count line became a principle: $n_after"
[ -f "$DEND/denials.jsonl" ] && python3 -c 'import json,sys
r = json.loads(open(sys.argv[1]).read().strip().splitlines()[-1])
sys.exit(0 if {"ts","hook","reason","cwd","front"} <= set(r) and r["hook"] == "scope-lock" else 1)' "$DEND/denials.jsonl" \
  && ok "every denial is recorded with the fence, the reason and the front" || fail "no usable denial record"

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
# The ERR trap has to INHERIT. Without `set -o errtrace` it is installed at the top level and
# silently absent inside functions, command substitutions and subshells -- which is exactly where
# the work happens, so a guard declaring RW_ON_CRASH=deny would fail OPEN in every helper.
RW_ERRTRACE="$(RW_HOOK=x RW_ON_CRASH=deny bash -c 'source hooks/lib.sh; f() { false; true; }; f' 2>&1 || true)"
printf '%s' "$RW_ERRTRACE" | grep -q '"permissionDecision": "deny"' \
  && ok "a failure inside a function fails closed (the ERR trap inherits)" || fail "ERR trap does not inherit into functions"
RW_NOTRACE="$(RW_HOOK=x RW_ON_CRASH=deny bash -c 'source hooks/lib.sh; set +o errtrace; f() { false; true; }; f; echo NO-TRAP' 2>&1 || true)"
printf '%s' "$RW_NOTRACE" | grep -q 'NO-TRAP' \
  && ok "and without errtrace the same failure passes silently (the check discriminates)" || fail "errtrace check does not discriminate"

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

# ── guard-commit ─────────────────────────────────────────────────────────────
section "guard-commit"
G="$TMP/git"; mkdir -p "$G"; git -C "$G" init -q; git -C "$G" config user.email t@t; git -C "$G" config user.name t
TR='--tr'; TR="${TR}ailer"
# The REASON has to name the flag. Asking only "did it deny?" passes with the flag check broken,
# because the empty-staging check denies the same command for its own reason -- measured with a
# planted defect, which is the whole point of refuting an assertion before trusting it.
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$G\",\"tool_input\":{\"command\":\"git commit $TR x -m m\"}}"
denied && printf '%s' "$OUT" | grep -q 'is forbidden in commits' \
  && ok "forbidden flag denied, and the reason names the flag" || fail "forbidden flag passed"
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
# These three sections measure the REVIEW path. It is no longer the default (plan_gate is born
# in preflight), so they declare it; a section that does not would be exercising a branch the
# gate never reaches and reporting green for it.
export CLAUDE_PLUGIN_OPTION_PLAN_GATE=review
P="$HOME_SANDBOX/.claude/plans"; printf '# plan\n\n## Goal\n' > "$P/my-plan.md"
export CLAUDE_PLUGIN_OPTION_PLANS_DIR="$P"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && ok "no review → denied" || fail "no review passed"
printf 'plan: my-plan.md\nround: 1\nVERDICT: APPROVED\n' > "$P/my-plan.review.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
! denied && ok "approved review by name → allowed" || fail "approved review denied"
printf '# plan edited\n\n## Goal\n' > "$P/my-plan.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
! denied && ok "editing the plan keeps the approval (what the user approved is what counts, no hash)" || fail "edit voided the approval"
printf 'plan: my-plan.md\nround: 2\nVERDICT: REJECTED\n' > "$P/my-plan.review.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
# The reason has to name the rejection. Asking only "did it deny?" passes with the REJECTED
# branch removed, because the verdict then falls through to "has no verdict" and denies anyway
# -- measured with a planted defect.
denied && printf '%s' "$OUT" | grep -q 'rejected the plan' \
  && ok "rejected review → denied, and the reason says it was rejected" || fail "rejected review passed"
printf 'plan: my-plan.md\nround: 3\nVERDICT: ESCALATE\n## Recomendações\n- x\n## Alternativas\n- y — fonte: RFC 0000\n' > "$P/my-plan.review.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && printf '%s' "$OUT" | grep -q "escalated" && ok "ESCALATE → denied until the user answers" || fail "ESCALATE passed"
printf 'plan: my-plan.md\nround: 3\nVERDICT: ESCALATE\n' > "$P/my-plan.review.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && printf '%s' "$OUT" | grep -q "malformed" && ok "ESCALATE without recommendations/alternatives/sources is named malformed" || fail "malformed escalation not named"
printf 'plan: my-plan.md\nround: 3\nVERDICT: APPROVED\n' > "$P/my-plan.review.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && printf '%s' "$OUT" | grep -q "ceiling" && ok "round 3 approved without the owner → denied (ceiling of 2)" || fail "round 3 passed without owner"
printf 'plan: my-plan.md\nround: 3\nowner: keep the plan, drop item 4\nVERDICT: APPROVED\n' > "$P/my-plan.review.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
! denied && ok "round 3 with the owner's decision → allowed" || fail "owner decision not honoured"
printf 'plan: my-plan.md\nround: 2\nsections-round1: Goal\nVERDICT: APPROVED\n' > "$P/my-plan.review.md"
printf '# plan\n\n## Goal\n\n## Overnight policy\n' > "$P/my-plan.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && printf '%s' "$OUT" | grep -q "grew" && ok "a section added after round 1 → denied (growth guard)" || fail "growth guard silent"
printf '# plan\n\n## Goal\n' > "$P/my-plan.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
! denied && ok "same sections as round 1 → allowed" || fail "growth guard false positive"
printf '# other plan\n' > "$P/other.md"; sleep 1; touch "$P/other.md"   # newest by mtime, no review
run_hook plan-review-gate "$(python3 -c 'import json; print(json.dumps({"tool_name":"ExitPlanMode","tool_input":{"plan":"# plan\n\n## Goal"}}))')"
! denied && ok "the submitted plan (by content) wins over the newest file in the shared directory" || fail "newest file chosen over the submitted plan"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && ok "without submitted text the newest file is the plan (other.md, unreviewed → denied)" || fail "fallback to newest broken"
rm "$P/other.md"
printf 'plan: ../x.md\nVERDICT: APPROVED\n' > "$P/evil.review.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && ok "review with '/' in plan name refused" || fail "path traversal accepted"
rm "$P/evil.review.md"
CLAUDE_PLUGIN_OPTION_PLAN_REVIEW_REQUIRED=false run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
! denied && ok "plan_review_required=false honoured" || fail "plan_review_required=false"
unset CLAUDE_PLUGIN_OPTION_PLANS_DIR

# ── plan-review-gate: the review inside the plan, and the project binding ────
section "plan-review-gate (plan mode writes one file)"
PB="$TMP/planbind"; RA="$TMP/repoA"; RB="$TMP/repoB"; mkdir -p "$PB" "$RA" "$RB"
git -C "$RA" init -q; git -C "$RB" init -q
export CLAUDE_PLUGIN_OPTION_PLANS_DIR="$PB"
ev() { printf '{"tool_name":"ExitPlanMode","cwd":"%s","tool_input":{}}' "$1"; }
# Plan mode lets the agent write ONE file. Requiring the review as a second file made the rite
# impossible there (measured 2026-09-13: a ten-minute review with twelve blockers could not be
# written down at all), so the review may live in a '## Review' section of the plan itself.
printf '# plan\nproject: %s\n\n## Goal\n\n## Review\nround: 1\nVERDICT: APPROVED\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
! denied && ok "review in a '## Review' section of the plan → allowed" || fail "in-plan review denied: $OUT"
printf '# plan\nproject: %s\n\n## Goal\n\n## Review\nround: 1\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
denied && ok "in-plan review without a verdict → denied" || fail "verdict-less in-plan review passed"
printf '# plan\nproject: %s\n\n## Goal\n\n## Review\nVERDICT: APPROVED\n' "$RA" > "$PB/a.md"
printf 'plan: a.md\nVERDICT: REJECTED\n' > "$PB/a.review.md"
run_hook plan-review-gate "$(ev "$RA")"
denied && ok "the sidecar review takes precedence over the in-plan section" || fail "sidecar ignored"
rm "$PB/a.review.md"
# The plans directory is shared by every project: 101 plans of several projects in one
# directory on the machine where this was measured, and the gate elected another project's.
printf '# plan\nproject: %s\n\n## Goal\n\n## Review\nVERDICT: APPROVED\n' "$RA" > "$PB/a.md"
sleep 1; printf '# other\nproject: %s\n\n## Goal\n' "$RB" > "$PB/b.md"   # newer, another project, unreviewed
run_hook plan-review-gate "$(ev "$RA")"
! denied && ok "a newer plan of another project does not win over this project's" || fail "cross-project plan elected"
run_hook plan-review-gate "$(ev "$RB")"
denied && printf '%s' "$OUT" | grep -q 'b.md' && ok "from the other repository its own plan is elected" || fail "project binding ignores the caller"
mkdir -p "$TMP/onlyother"; printf '# other\nproject: %s\n\n## Goal\n' "$RB" > "$TMP/onlyother/b.md"
CLAUDE_PLUGIN_OPTION_PLANS_DIR="$TMP/onlyother" run_hook plan-review-gate "$(ev "$RA")"
denied && printf '%s' "$OUT" | grep -q 'belongs to another project' && ok "another project's plan is named, not asked for a review" || fail "cryptic denial for another project's plan"
# One directory, two names: /var is a link to /private/var on macOS, so a declared path and a
# `git rev-parse` root differ as strings. Both sides are resolved before comparing.
printf '# plan\nproject: %s\n\n## Goal\n\n## Review\nVERDICT: APPROVED\n' "$(cd "$RA" && pwd -P)" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
! denied && ok "a project declared through a resolved path still matches" || fail "symlinked project path treated as another project"
# The in-plan review's own heading is not growth.
printf '# plan\nproject: %s\n\n## Goal\n\n## Review\nround: 2\nsections-round1: Goal\nVERDICT: APPROVED\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
! denied && ok "the review's own heading does not trip the growth guard" || fail "in-plan review counted as growth"
printf '# plan\nproject: %s\n\n## Goal\n\n## New\n\n## Review\nround: 2\nsections-round1: Goal\nVERDICT: APPROVED\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
denied && printf '%s' "$OUT" | grep -q 'grew' && ok "a real new section still denies" || fail "growth guard broken"
# A superseded plan is not a candidate: that is how the documentation norm retires one, and the
# gate reads the same vocabulary docs-check.sh reads (.roadworthy/docs.json, "status").
printf '# plan\nproject: %s\nstatus: superseded by b.md\n\n## Goal\n' "$RA" > "$PB/a.md"
printf '# plan\nproject: %s\n\n## Goal\n\n## Review\nVERDICT: APPROVED\n' "$RA" > "$PB/b.md"
run_hook plan-review-gate "$(ev "$RA")"
! denied && ok "a plan marked superseded is not elected" || fail "superseded plan elected: $OUT"
mkdir -p "$RA/.roadworthy"; printf '{"status":{"superseded by":"superado por"}}' > "$RA/.roadworthy/docs.json"
printf '# plan\nproject: %s\nstatus: superado por b.md\n\n## Goal\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
! denied && ok "the project's own word for superseded is recognised" || fail "project status vocabulary ignored: $OUT"
# Two live plans of one project and nothing to tell them apart: refuse naming both. Electing the
# newest by date submitted a stale draft in the field (2026-09-13).
printf '# plan\nproject: %s\n\n## Goal\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
denied && printf '%s' "$OUT" | grep -q 'a.md, b.md' && ok "two live plans of one project → denied, both named" || fail "ambiguous plans not refused: $OUT"
# A directory of undeclared legacy drafts is NOT judged that way: it would block every user on
# upgrade. The old fallback still elects the newest.
mkdir -p "$TMP/legacy"; printf '# one\n' > "$TMP/legacy/one.md"; printf '# two\n' > "$TMP/legacy/two.md"
CLAUDE_PLUGIN_OPTION_PLANS_DIR="$TMP/legacy" run_hook plan-review-gate "$(ev "$RA")"
denied && printf '%s' "$OUT" | grep -q 'no review for the current plan' && ok "undeclared drafts are not blocked as ambiguous" || fail "legacy drafts refused as ambiguous: $OUT"
# A front written against a tag, with the tree ahead of it: plan and review must name the same
# base, and the base must resolve.
(cd "$RA" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base && git tag v0)
printf '# plan\nproject: %s\nstatus: superado por a.md\n\n## Goal\n' "$RA" > "$PB/b.md"
printf '# plan\nproject: %s\nbase: v0\n\n## Goal\n\n## Review\nbase: v0\nVERDICT: APPROVED\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
! denied && ok "plan and review declaring the same base → allowed" || fail "same base denied: $OUT"
printf '# plan\nproject: %s\nbase: v0\n\n## Goal\n\n## Review\nVERDICT: APPROVED\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
denied && printf '%s' "$OUT" | grep -q 'the working tree' && ok "a review with no base, on a plan that declares one → denied" || fail "baseless review passed: $OUT"
printf '# plan\nproject: %s\nbase: v0\n\n## Goal\n\n## Review\nbase: HEAD\nVERDICT: APPROVED\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
denied && printf '%s' "$OUT" | grep -q "declares base 'v0'" && ok "a review made against another base → denied" || fail "wrong base passed: $OUT"
printf '# plan\nproject: %s\nbase: v-nope\n\n## Goal\n\n## Review\nbase: v-nope\nVERDICT: APPROVED\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
denied && printf '%s' "$OUT" | grep -q 'does not resolve' && ok "a base that does not resolve → denied, naming the ref" || fail "unresolvable base passed: $OUT"
unset CLAUDE_PLUGIN_OPTION_PLANS_DIR

# ── refute.sh (refuted with a toy check) ─────────────────────────────────────
unset CLAUDE_PLUGIN_OPTION_PLAN_GATE

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
# The record is written by the script, not by whoever reports the result. A refutation that exists
# only as a sentence in a report is precisely what this tool replaces.
RLED="$TMP/rwdata-refute/refutations.jsonl"
ROADWORTHY_DATA="$TMP/rwdata-refute" bash skills/refute/scripts/refute.sh --file "$T/config.txt" --sed 's/42/43/' --expect 'answer is not 42' -- "$T/check.sh" >/dev/null
[ -f "$RLED" ] && python3 -c 'import json,sys
r = json.loads(open(sys.argv[1]).read().strip().splitlines()[-1])
need = {"ts","file","sha_before","sha_after","restored","injection","expect","exit_red","exit_clean","check_cmd","head"}
missing = need - set(r)
sys.exit(0 if not missing and r["restored"] and r["exit_red"] != 0 and r["exit_clean"] == 0 else 1)' "$RLED" \
  && ok "refute.sh records the refutation itself, with both hashes and both exit codes" || fail "no usable refutation record"
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

# ── plan-review-gate: review_suffix and Portuguese fields ───────────────────
section "plan-review-gate (review_suffix)"
export CLAUDE_PLUGIN_OPTION_PLAN_GATE=review
export CLAUDE_PLUGIN_OPTION_PLANS_DIR="$P"
printf '# plano\n' > "$P/outro.md"; sha="$(shasum -a 256 "$P/outro.md" | cut -d' ' -f1)"
printf 'plano: outro.md\nplano-sha256: %s\nVEREDITO: APROVADO\n' "$sha" > "$P/outro.banca.md"
CLAUDE_PLUGIN_OPTION_REVIEW_SUFFIX=.banca.md run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
! denied && ok "custom suffix + Portuguese fields accepted" || fail "custom suffix rejected: $OUT"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && ok "default suffix ignores the .banca.md review" || fail "default suffix accepted wrong file"
unset CLAUDE_PLUGIN_OPTION_PLANS_DIR

# ── docs-init: idempotent tree by role ──────────────────────────────────────
unset CLAUDE_PLUGIN_OPTION_PLAN_GATE

section "docs-init.sh"
DI="$TMP/di"; mkdir -p "$DI"
bash skills/document/scripts/docs-init.sh "$DI" > "$TMP/di1.log" && ok "first run creates the tree" || fail "docs-init first run"
grep -q 'created  docs/decisions/' "$TMP/di1.log" && [ -f "$DI/docs/README.md" ] && [ -f "$DI/docs/plans/done/README.md" ] && ok "map, roles and done index created" || fail "tree incomplete"
# The generated docs.json carries the status dictionary, EMPTY and uncommented: docs-check.sh and
# plan-review-gate read it with json.load, and one "//" would break the documentation gate of
# every new project. A project that never declares a word keeps English, which is the default.
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("status")=={} else 1)' "$DI/.roadworthy/docs.json" \
  && ok "the generated docs.json has an empty status dictionary and parses as JSON" || fail "generated docs.json has no usable status key"
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
# The pointer has to be READ in the word the project declares -- here Portuguese, set above in
# this tree's docs.json. A pointer the script cannot read is a pointer it ignores, and ignoring it
# means handing back the SUPERSEDED hand-off as if it were current (measured 2026-09-07 on a real
# project: the newest file by name was marked "superado por" and the script printed it anyway).
printf 'status: superado por 2026-01-01-0900-handoff-a.md\n' > "$DI/docs/plans/2026-01-02-0900-handoff-b.md"
! bash skills/resume/scripts/resume-pick.sh "$DI" >/dev/null 2>&1 \
  && ok "a superseded-by written in the project word is READ, not ignored" || fail "resume ignored the project vocabulary and returned the superseded hand-off"
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
# The state is written in BOTH places: the shared data directory may belong to another project,
# and reporting "passed" for a front full of gaps is how a resume lies to the next session.
[ "$(cat "$CF/.roadworthy/state")" = "passed" ] && ok "the state is recorded in the project too" || fail "project state: $(cat "$CF/.roadworthy/state" 2>&1)"
# Discriminating on purpose: the two copies are made to DISAGREE, so the assertion can only pass
# by reading the project one. With both saying "passed" it passed either way and measured
# nothing -- caught by planting the defect.
printf 'needs_human\n' > "$ROADWORTHY_DATA/state"
[ "$( (cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh" --state) )" = "passed" ] && ok "--state reads the project copy, not the shared one" || fail "--state read the wrong copy"
printf 'passed\n' > "$ROADWORTHY_DATA/state"
# A gate that cannot go red is a green light, not a measurement. It warns; what refuses is that
# every gate has to come from the plan.
CLOSE_OUT="$( (cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh" --check) 2>&1 || true )"
printf '%s' "$CLOSE_OUT" | grep -q 'cannot fail' && ok "a gate that cannot fail is named, not silently accepted" || fail "trivial gate accepted in silence: $CLOSE_OUT"
CHK="$( (cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh" --check) 2>&1 )"
printf '%s' "$CHK" | grep -q 'FRESH     true' && ok "--check reports FRESH on the same tree" || fail "not FRESH; --check said: $CHK"
echo y >> "$CF/docs/README.md"
CHK="$( (cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh" --check) 2>&1 || true )"
printf '%s' "$CHK" | grep -q 'STALE' && ok "--check reports STALE after an edit" || fail "not STALE after edit; --check said: $CHK"
git -C "$CF" checkout -q -- docs/README.md
printf 'false\n' > "$CF/.roadworthy/gates"; printf 'docs/**\n' > "$CF/.roadworthy/scope"; git -C "$CF" add -A; git -C "$CF" commit -q -m red
! (cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh") >/dev/null 2>&1 && [ -f "$CF/.roadworthy/scope" ] && [ "$(cat "$ROADWORTHY_DATA/state")" = "gaps_found" ] && ok "red gate → gaps_found, scope kept" || fail "red gate handling"
(cd "$CF" && bash "$ROOT/skills/close/scripts/close.sh" --needs-human "device bench") >/dev/null && [ "$(cat "$ROADWORTHY_DATA/state")" = "needs_human" ] && ok "--needs-human records the state" || fail "needs_human"
# Nothing measured is not "everything fresh". --check used to print the absence and exit 0, which
# is what let a night close claiming every gate FRESH with zero gates (measured 2026-09-13 on this
# repository, which had no .roadworthy/gates at all and a scope six days past its front).
NG="$TMP/nogates"; mkdir -p "$NG/.roadworthy"; git -C "$NG" init -q
(cd "$NG" && printf 'x\n' > f && git -c user.email=t@t -c user.name=t add -A && git -c user.email=t@t -c user.name=t commit -q -m base)
! (cd "$NG" && ROADWORTHY_DATA="$TMP/ngdata" bash "$ROOT/skills/close/scripts/close.sh" --check) >/dev/null 2>&1 && ok "--check without a gates file fails" || fail "--check passed with no gates file"
printf '# only a comment\n\n' > "$NG/.roadworthy/gates"; printf 'f\n' > "$NG/.roadworthy/scope"
git -C "$NG" -c user.email=t@t -c user.name=t add -A; git -C "$NG" -c user.email=t@t -c user.name=t commit -q -m gates
! (cd "$NG" && ROADWORTHY_DATA="$TMP/ngdata" bash "$ROOT/skills/close/scripts/close.sh" --check) >/dev/null 2>&1 && ok "--check on a gates file that declares none fails" || fail "--check passed with zero declared gates"
! (cd "$NG" && ROADWORTHY_DATA="$TMP/ngdata" bash "$ROOT/skills/close/scripts/close.sh") >/dev/null 2>&1 && [ -f "$NG/.roadworthy/scope" ] && ok "close with zero declared gates fails and keeps the scope" || fail "close released the scope with nothing measured"
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
# An index split by theme: MEMORY.md links a sub-index, the sub-index links the leaf (measured 2026-09-07:
# 51 false orphans on a project whose history lived in one sub-index).
printf '# idx\n- [one](feedback_one.md)\n- [history](project_history.md)\n' > "$PC/mem/MEMORY.md"
printf -- '- [leaf](project_leaf.md)\n' > "$PC/mem/project_history.md"; : > "$PC/mem/project_leaf.md"
bash skills/document/scripts/pointers-check.sh "$PC/CLAUDE.md" --root "$PC" --memory "$PC/mem" >/dev/null && ok "memory file reached through a sub-index is not an orphan" || fail "sub-indexed memory counted as orphan"
: > "$PC/mem/project_orphan.md"
! bash skills/document/scripts/pointers-check.sh "$PC/CLAUDE.md" --root "$PC" --memory "$PC/mem" >/dev/null 2>&1 && ok "a file no index reaches still fails" || fail "orphan passed next to a sub-index"
rm "$PC/mem/project_orphan.md"

# ── refute-ledger ───────────────────────────────────────────────────────────
section "refute-ledger.sh"
RL="$TMP/rl"; mkdir -p "$RL"
printf '// FENCE: x\n// checks y\n// refuted 2026-01-01: injected z → Actual: red\n' > "$RL/a_test.dart"
printf '// FENCE: without record\n// checks y\n' > "$RL/b_test.dart"
printf '// plain test\n' > "$RL/c_test.dart"
! bash skills/refute/scripts/refute-ledger.sh "$RL" >/dev/null 2>&1 && ok "fence without a refutation record fails" || fail "unrecorded fence passed"
# A project whose fences are not named like tests declares them by name. Held to a DATED record,
# because the loose default is satisfied by prose: hooks/principles contains the word "Injects"
# in its description and passed the ledger with no refutation at all -- measured.
RLD="$TMP/rl-declared"; mkdir -p "$RLD"
printf 'not a fence by name\n' > "$RLD/plain-guard"
! bash skills/refute/scripts/refute-ledger.sh "$RLD" --sources plain-guard >/dev/null 2>&1 \
  && ok "a declared fence with no dated record fails" || fail "declared fence without a record passed"
printf 'guard\n# Refuted 2026-09-13: injected x; went red with y\n' > "$RLD/plain-guard"
bash skills/refute/scripts/refute-ledger.sh "$RLD" --sources plain-guard --legacy /dev/null | grep -q '1 fence(s)' \
  && ok "and passes once it carries one" || fail "declared fence with a record still failed"
! bash skills/refute/scripts/refute-ledger.sh "$RLD" --sources nao-existe >/dev/null 2>&1 \
  && ok "a declared fence that does not exist is a hole, not an absence of obligation" || fail "missing declared fence passed"
printf 'guard\n# this text merely contains the word inject, which is not a record\n' > "$RLD/plain-guard"
! bash skills/refute/scripts/refute-ledger.sh "$RLD" --sources plain-guard >/dev/null 2>&1 \
  && ok "prose containing 'inject' does not count as a record for a declared fence" || fail "prose accepted as a refutation record"
rm -f "$RLD/plain-guard"
# The plugin's own guards are in the ledger, and the gates file runs it.
bash skills/refute/scripts/refute-ledger.sh hooks --sources principles,protect-paths,scope-lock,guard-commit,overnight-guard,plan-review-gate | grep -q '6 fence(s), 0 legacy, 0 without' \
  && ok "the plugin's own six guards are declared fences and all carry a dated record" || fail "the plugin does not hold its own guards to the ledger"
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
# The night belongs to the repository the COMMAND acts on. Resolving from the session cwd
# denied a push to an unmarked repository just because the session stood in a marked one.
OTHER="$TMP/othernight"; mkdir -p "$OTHER"; git -C "$OTHER" init -q
run_hook overnight-guard "{\"tool_name\":\"Bash\",\"cwd\":\"$ON\",\"tool_input\":{\"command\":\"git -C $OTHER push origin main\"}}"
! denied && ok "a push to another, unmarked repository passes from inside a marked one" || fail "the night denied another repository"
run_hook overnight-guard "{\"tool_name\":\"Bash\",\"cwd\":\"$OTHER\",\"tool_input\":{\"command\":\"git -C $ON push origin main\"}}"
denied && ok "and a push to the MARKED repository is denied from outside it" || fail "the night missed the repository the command attacks"

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
printf '# plan\n' > "$OV/docs/plans/2026-01-02-0300-bare.md"
! (cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0300-bare.md night) >/dev/null 2>"$TMP/ov2b" && grep -q '3 precondition' "$TMP/ov2b" && grep -q 'no review' "$TMP/ov2b" && grep -q 'Overnight policy' "$TMP/ov2b" && grep -q 'dirty' "$TMP/ov2b" && ok "start lists EVERY missing precondition at once (review, policy, dirty tree)" || fail "preconditions not listed together: $(cat "$TMP/ov2b")"
rm "$OV/docs/plans/2026-01-02-0300-bare.md"
printf 'plan: 2026-01-02-0100-night.md\nVERDICT: APPROVED\n' > "$OV/docs/plans/2026-01-02-0100-night.review.md"
! (cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0100-night.md night) >/dev/null 2>"$TMP/ov3" && grep -q 'dirty' "$TMP/ov3" && ok "start refused on a dirty tree (approved review not committed)" || fail "start on dirty tree: $(cat "$TMP/ov3")"
git -C "$OV" add -A; git -C "$OV" commit -q -m review
printf '# plan without policy\n' > "$OV/docs/plans/2026-01-02-0200-nopolicy.md"
sha2="$(shasum -a 256 "$OV/docs/plans/2026-01-02-0200-nopolicy.md" | cut -d' ' -f1)"
printf 'plan: x\nplan-sha256: %s\nVERDICT: APPROVED\n' "$sha2" > "$OV/docs/plans/2026-01-02-0200-nopolicy.review.md"
git -C "$OV" add -A; git -C "$OV" commit -q -m nopolicy
! (cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0200-nopolicy.md night) >/dev/null 2>"$TMP/ov4" && grep -q 'Overnight policy' "$TMP/ov4" && ok "start refused on a plan without the Overnight policy section" || fail "start without policy section"
printf '# plano\n\n## Política da madrugada\n- nada.\n' > "$OV/docs/plans/2026-01-02-0400-pt.md"
printf 'plan: 2026-01-02-0400-pt.md\nVERDICT: APPROVED\n' > "$OV/docs/plans/2026-01-02-0400-pt.review.md"
! (cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0400-pt.md night) >/dev/null 2>"$TMP/ov4b" && grep -q 'dirty' "$TMP/ov4b" && ! grep -q 'Overnight policy' "$TMP/ov4b" && ok "a plan titled 'Política da madrugada' is refused only for what is really missing (dirty tree), not for the title" || fail "PT title refused: $(cat "$TMP/ov4b")"
rm "$OV/docs/plans/2026-01-02-0400-pt.md" "$OV/docs/plans/2026-01-02-0400-pt.review.md"
t0="$(python3 -c 'import time; print(int(time.time()*1000))')"
diary="$(cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0100-night.md night | tail -1)"
t1="$(python3 -c 'import time; print(int(time.time()*1000))')"
[ -f "$OV/.roadworthy/overnight" ] && [ -f "$OV/$diary" ] && ok "start writes the marker and the diary ($diary)" || fail "start did not write marker/diary"
# The diary is written by a script, so its status line is the project's word, never hardcoded.
head -1 "$OV/$diary" | grep -q '^status: accepted$' \
  && ok "the diary carries the status word (English here: this project declares none)" || fail "diary status line: $(head -1 "$OV/$diary")"
DIARY_PT="$(sed -e "s|{{status}}|aceito|" "$ROOT/skills/overnight/templates/diary.md" | head -1)"
[ "$DIARY_PT" = "status: aceito" ] && ok "the diary template takes the word from the placeholder, not from a literal" || fail "diary template still hardcodes a word: $DIARY_PT"
HANDOFF_PT="$(sed -e "s|{{status}}|aceito|" "$ROOT/skills/overnight/templates/handoff.md" | head -1)"
[ "$HANDOFF_PT" = "status: aceito" ] && ok "and so does the hand-off template" || fail "hand-off template still hardcodes a word: $HANDOFF_PT"
ms="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["started_ms"])' "$OV/.roadworthy/overnight")"
[ "$ms" -ge "$t0" ] && [ "$ms" -le "$t1" ] && ok "started_ms was measured by the script (within the test's clock window)" || fail "started_ms outside window: $t0 ≤ $ms ≤ $t1"
! (cd "$OV" && bash "$S/overnight-start.sh" docs/plans/2026-01-02-0100-night.md night) >/dev/null 2>"$TMP/ov5" && grep -q 'already on' "$TMP/ov5" && ok "start refused while the marker exists" || fail "double start accepted"
! (cd "$OV" && bash "$S/overnight-entry.sh" --phase F1 --decision d --reason r) >/dev/null 2>"$TMP/ov6" && grep -q -- '--source' "$TMP/ov6" && ok "entry refused without a source" || fail "entry without source accepted"
# A source has to be openable. "RFC 0000 §1" was accepted here for a year and is exactly the
# shape the rule exists to refuse: a citation nobody can follow.
! (cd "$OV" && bash "$S/overnight-entry.sh" --phase F1 --decision d --reason r --source "RFC 0000 §1") >/dev/null 2>&1 \
  && ok "a source that is only a sentence is refused" || fail "unopenable source accepted"
! (cd "$OV" && bash "$S/overnight-entry.sh" --phase F1 --decision d --reason r --source "docs/nao-existe.md") >/dev/null 2>&1 \
  && ok "a path that does not exist is refused" || fail "missing path accepted as a source"
(cd "$OV" && bash "$S/overnight-entry.sh" --phase F1 --decision "use X" --reason "spec says so" --source "https://example.invalid/spec#1" --ratify) >/dev/null \
  && grep -q -E '^- `[0-9]{13}` · [0-9T:Z-]+ · \*\*F1\*\* · use X · reason: spec says so · source: https://example.invalid/spec#1 · ratify in the morning$' "$OV/$diary" \
  && ok "entry carries epoch ms + ISO taken by the script, under Decisions" || fail "entry format: $(grep 'use X' "$OV/$diary")"
(cd "$OV" && bash "$S/overnight-entry.sh" --phase F1 --decision d2 --reason r --source "docs/plans/2026-01-02-0100-night.md") >/dev/null \
  && ok "an existing file is a source" || fail "existing file refused as a source"
(cd "$OV" && bash "$S/overnight-entry.sh" --phase F1 --decision d3 --reason r --source HEAD) >/dev/null \
  && ok "a git ref that resolves is a source" || fail "git ref refused as a source"
(cd "$OV" && bash "$S/overnight-entry.sh" --blocker "pricing is the user's") >/dev/null && python3 - "$OV/$diary" <<'PY' && ok "blocker lands under its own section" || fail "blocker section"
import sys; t=open(sys.argv[1]).read(); i=t.index("## Blockers for the morning"); j=t.index("## Delivery"); sys.exit(0 if "pricing is the user's" in t[i:j] else 1)
PY
(cd "$OV" && bash "$S/overnight-entry.sh" --phase-done F1 --sha abc1234 --gates "suite green") >/dev/null && grep -q '^| F1 | `abc1234` | suite green |' "$OV/$diary" && [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["phase"])' "$OV/.roadworthy/overnight")" = "F1" ] && ok "phase ledger row; marker phase follows" || fail "phase ledger row / marker phase"
export ROADWORTHY_DATA="$TMP/ovdata"
! (cd "$OV" && bash "$S/overnight-close.sh") >/dev/null 2>"$TMP/ov7" && grep -q 'dirty' "$TMP/ov7" && ok "close refused on a dirty tree (the diary is uncommitted)" || fail "close on dirty tree"
git -C "$OV" add -A; git -C "$OV" commit -q -m diary
! (cd "$OV" && bash "$S/overnight-close.sh") >/dev/null 2>"$TMP/ov8" && grep -q -E 'STALE|MISSING' "$TMP/ov8" && [ -f "$OV/.roadworthy/overnight" ] && ok "close refused while a gate is MISSING; marker kept" || fail "close without evidence accepted"
# A night must not close with nothing measured: with no gate declared, close.sh fails and the
# refusal reaches here instead of being read as "every gate FRESH".
printf '# no gate declared\n' > "$OV/.roadworthy/gates"
git -C "$OV" -c user.email=t@t -c user.name=t commit -qam 'no gates'
! (cd "$OV" && bash "$S/overnight-close.sh") >/dev/null 2>"$TMP/ov9" && grep -q 'no gate' "$TMP/ov9" && [ -f "$OV/.roadworthy/overnight" ] && ok "the night refuses to close with no gate declared; marker kept" || fail "night closed with nothing measured: $(cat "$TMP/ov9")"
printf 'true\n' > "$OV/.roadworthy/gates"
git -C "$OV" -c user.email=t@t -c user.name=t commit -qam 'gates back'
# The night started against a specific plan, and its hash has been recorded since 0.3.0 with
# nobody reading it: the plan could be rewritten mid-night and the morning would never know.
printf '# plan\n\n## Overnight policy\n- rewritten mid-night.\n' > "$OV/docs/plans/2026-01-02-0100-night.md"
git -C "$OV" -c user.email=t@t -c user.name=t commit -qam 'plan rewritten'
! (cd "$OV" && bash "$S/overnight-close.sh" --run) >/dev/null 2>"$TMP/ovsha" && grep -q 'the plan changed during the night' "$TMP/ovsha" \
  && ok "the night refuses to close when the plan changed under it" || fail "plan rewritten mid-night and the close did not notice: $(cat "$TMP/ovsha")"
python3 - "$OV/.roadworthy/overnight" "$OV/docs/plans/2026-01-02-0100-night.md" <<'PY'
import hashlib, json, sys
m = json.load(open(sys.argv[1]))
m["plan_sha256"] = hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest()
json.dump(m, open(sys.argv[1], "w"), indent=1)
PY
git -C "$OV" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1 || true
git -C "$OV" -c user.email=t@t -c user.name=t commit -qam 'marker' >/dev/null 2>&1 || true
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

# ── stop-gate: "done" does not pass on stale gates ──────────────────────────
section "stop-gate"
# Exit 2 is what blocks a turn, and the reason goes to stderr -- the Stop event has its own
# contract, opposite to every other hook here.
SG="$TMP/stop"; SGD="$TMP/stopdata"; mkdir -p "$SG/.roadworthy" "$SGD"
git -C "$SG" init -q; git -C "$SG" config user.email t@t; git -C "$SG" config user.name t
echo x > "$SG/f"; git -C "$SG" add -A; git -C "$SG" commit -q -m base
sg() {  # sg <session> <final message>  -> SGRC, SGERR
  set +e
  printf '{"session_id":"%s","cwd":"%s","last_assistant_message":"%s"}' "$1" "$SG" "$2" \
    | ROADWORTHY_DATA="$SGD" bash "$ROOT/hooks/run-hook.cmd" stop-gate >/dev/null 2>"$TMP/sg.err"
  SGRC=$?
  set -e
  SGERR="$(cat "$TMP/sg.err")"
}
# Without a gates file it must NEVER block: close.sh --check fails there by design, and blocking
# on that would be a false positive in nearly every project.
sg noGates "All done."
[ "$SGRC" -ne 2 ] && ok "no gates declared: the turn is never blocked" || fail "blocked a project with no gates declared"
printf 'true\n' > "$SG/.roadworthy/gates"; git -C "$SG" add -A; git -C "$SG" commit -q -m gates
# Claiming completion with a gate that was never measured.
sg s1 "All done."
[ "$SGRC" -eq 2 ] && ok "a finished claim on gates that were never measured is blocked (exit 2)" || fail "stale gates passed: rc=$SGRC $SGERR"
printf '%s' "$SGERR" | grep -q 'MISSING' && ok "and the block shows the state of each gate" || fail "the block did not show the gate states: $SGERR"
# Not blocked twice on the same tree: a wall that repeats is a loop.
sg s1 "All done."
[ "$SGRC" -ne 2 ] && ok "the same tree is not blocked twice in a session" || fail "the latch did not hold: a blocked turn loops"
# A changed tree is blocked again: the latch is not a single shot.
echo y >> "$SG/f"; git -C "$SG" commit -qam changed
sg s1 "All done."
[ "$SGRC" -eq 2 ] && ok "a changed tree is blocked again (the latch is keyed on the tree, not the session)" || fail "the latch became a single shot"
# Saying nothing about being finished is not a claim.
sg s2 "Here is what I found so far; two things are still open."
[ "$SGRC" -ne 2 ] && ok "a turn that does not claim completion is never blocked" || fail "blocked an honest report"
# With the gates actually measured on this tree, the claim passes -- in a session that has never
# been latched, so the pass is the gates and not the latch.
(cd "$SG" && ROADWORTHY_DATA="$SGD" bash "$ROOT/skills/close/scripts/close.sh") >/dev/null 2>&1 || true
sg fresh "All done."
[ "$SGRC" -ne 2 ] && ok "with every gate FRESH the claim passes, in a session with no latch" || fail "fresh gates still blocked: $SGERR"
# Fails open, by declaration: no repository, no message, no transcript.
NOGIT2="$TMP/nogit-stop"; mkdir -p "$NOGIT2"
set +e
printf '{"session_id":"s3","cwd":"%s","last_assistant_message":"All done."}' "$NOGIT2" \
  | ROADWORTHY_DATA="$SGD" bash "$ROOT/hooks/run-hook.cmd" stop-gate >/dev/null 2>&1
[ $? -ne 2 ] && ok "outside a git repository it never blocks" || fail "blocked outside a repository"
printf '{"session_id":"s4","cwd":"%s"}' "$SG" | ROADWORTHY_DATA="$SGD" bash "$ROOT/hooks/run-hook.cmd" stop-gate >/dev/null 2>&1
[ $? -ne 2 ] && ok "with no final message and no transcript it never blocks" || fail "blocked with nothing to read"
CLAUDE_PLUGIN_OPTION_STOP_GATE=false bash -c 'printf "{\"session_id\":\"s5\",\"cwd\":\"'"$SG"'\",\"last_assistant_message\":\"All done.\"}" | ROADWORTHY_DATA="'"$SGD"'" bash "'"$ROOT"'/hooks/run-hook.cmd" stop-gate' >/dev/null 2>&1
[ $? -ne 2 ] && ok "stop_gate=false honoured" || fail "stop_gate=false ignored"
set -e

# ── rite-gate: the rite stops being optional ────────────────────────────────
section "rite-gate"
# Measured on this repository on 2026-09-13: 60 edits, 117 shell commands, ZERO rite invocations,
# with the plugin installed and active, and nothing noticed. This is the wall for that.
RG="$TMP/rite"; mkdir -p "$RG/.roadworthy" "$RG/src"; git -C "$RG" init -q
rg() { run_hook rite-gate "{\"tool_name\":\"$1\",\"cwd\":\"$RG\",\"tool_input\":$2}"; }

rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
denied && ok "no front: an edit is denied, naming the rite that opens one" || fail "edit passed with no front"
rg Bash "{\"command\":\"echo x > $RG/src/a.py\"}"
denied && ok "no front: a shell write is denied too (117 of 177 acts went this way)" || fail "shell write passed with no front"
rg Bash "{\"command\":\"grep -n '>' $RG/src/a.py\"}"
! denied && ok "a read with > inside quotes is not a write" || fail "quoted > read as a redirection"
rg Bash "{\"command\":\"echo \$(date) is fine\"}"
! denied && ok "a command substitution is not a redirection" || fail "command substitution read as a write"
for verb in "tee $RG/src/a.py" "cp /etc/hosts $RG/src/a.py" "mv /tmp/x $RG/src/a.py" "sed -i s/a/b/ $RG/src/a.py" "dd of=$RG/src/a.py"; do
  rg Bash "{\"command\":\"$verb\"}"
  denied || fail "write verb passed with no front: $verb"
done
ok "tee, cp, mv, sed -i and dd of= are writes too"
# An empty scope file used to satisfy every check while switching the lock off: one `touch` and
# both fences were gone at once.
: > "$RG/.roadworthy/scope"
rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
denied && ok "an empty scope file does not open a front" || fail "an empty scope file opens a front"
printf '# only a comment\n\n' > "$RG/.roadworthy/scope"
rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
denied && ok "nor does one that declares only comments" || fail "a comment-only scope opens a front"
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$RG\",\"tool_input\":{\"file_path\":\"$RG/src/a.py\"}}"
# The REASON has to name the malformed front. Asking only "did it deny?" passes with the check
# removed, because an empty glob list matches nothing and the lock denies for that instead --
# measured with a planted defect.
denied && printf '%s' "$OUT" | grep -q 'declares no glob' \
  && ok "and the lock calls it a malformed front instead of standing down" || fail "empty scope switched the lock off"
# With a real front, work proceeds.
printf 'src/**\n' > "$RG/.roadworthy/scope"
rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
! denied && ok "with a front open, the edit proceeds" || fail "open front still denied"
rg Bash "{\"command\":\"echo x > $RG/src/a.py\"}"
! denied && ok "and so does the shell write" || fail "open front denied a shell write"
# The foundation is written by scripts, with or without a front.
for f in scope gates plan.snapshot state evidence.jsonl denials.jsonl refutations.jsonl preflight.jsonl readings.jsonl; do
  rg Edit "{\"file_path\":\"$RG/.roadworthy/$f\"}"
  denied || fail "the foundation file $f is editable by hand"
done
ok "no foundation file is editable by hand, front or no front"
# The same door, through the shell. Guarding only the edit tools left the exact hole the roadmap
# recorded from the field -- appending a glob to .roadworthy/scope with a justification quoted
# from the chat -- open one `>>` away, and only while a front WAS open, which is when it matters.
printf 'src/**\n' > "$RG/.roadworthy/scope"
rg Bash "{\"command\":\"echo docs/** >> $RG/.roadworthy/scope\"}"
denied && ok "the scope cannot be widened through the shell either, front open or not" || fail "the shell widened the scope"
rg Bash "{\"command\":\"cp /dev/null $RG/.roadworthy/plan.snapshot\"}"
denied || fail "the shell rewrote the snapshot"
rg Bash "{\"command\":\"tee $RG/.roadworthy/evidence.jsonl\"}"
denied || fail "the shell rewrote the evidence ledger"
ok "nor can the snapshot or the evidence ledger"
rg Bash "{\"command\":\"echo x > $RG/.roadworthy/protected\"}"
! denied && ok "and human configuration is still writable through the shell" || fail "the shell was denied human configuration"
for f in docs.json protected overnight-rules; do
  rg Edit "{\"file_path\":\"$RG/.roadworthy/$f\"}"
  ! denied || fail "human configuration $f denied by the rite gate"
done
ok "human configuration of the project stays editable"
# The plan is the artefact of the rite itself, and lives outside the project.
RGP="$TMP/riteplans"; mkdir -p "$RGP"
rm -f "$RG/.roadworthy/scope"
CLAUDE_PLUGIN_OPTION_PLANS_DIR="$RGP" run_hook rite-gate "{\"tool_name\":\"Write\",\"cwd\":\"$RG\",\"tool_input\":{\"file_path\":\"$RGP/a-plan.md\"}}"
! denied && ok "the plan file is writable with no front: it is what opens one" || fail "the rite gate denied the plan itself"
# A front that ended badly blocks the next one; no state at all is a new project.
rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
printf '%s' "$OUT" | grep -q 'no front is open' && ok "with no state recorded, the refusal is about the missing front, not about a past one" || fail "no-state case reported as a bad state"
printf 'gaps_found\n' > "$RG/.roadworthy/state"
rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
denied && printf '%s' "$OUT" | grep -q 'ended as' && ok "a front that ended in gaps blocks the next one, and says so" || fail "gaps_found did not block: $OUT"
printf 'passed\n' > "$RG/.roadworthy/state"
rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
printf '%s' "$OUT" | grep -q 'no front is open' && ok "a front that passed does not block the next one" || fail "passed state blocked the next front"
rm -f "$RG/.roadworthy/state"
# Outside a git repository the gate is inert: it has no project to protect.
NOGIT="$TMP/nogit-rite"; mkdir -p "$NOGIT"
run_hook rite-gate "{\"tool_name\":\"Edit\",\"cwd\":\"$NOGIT\",\"tool_input\":{\"file_path\":\"$NOGIT/a.py\"}}"
! denied && ok "outside a git repository the gate is inert" || fail "the gate denied outside a repository"
CLAUDE_PLUGIN_OPTION_RITE_GATE=false rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
! denied && ok "rite_gate=false honoured" || fail "rite_gate=false ignored"

# ── scope-write + the closing measured against the snapshot ─────────────────
section "scope-write.sh / plan.snapshot"
SW="$TMP/sw"; SWD="$TMP/swdata"; mkdir -p "$SW/src" "$SWD"
git -C "$SW" init -q; git -C "$SW" config user.email t@t; git -C "$SW" config user.name t
echo base > "$SW/src/a.txt"
printf '# P\n## Escopo\n```\nsrc/**\nplan.md\n```\n## Verificação\n```\ntrue\n```\n' > "$SW/plan.md"
git -C "$SW" add -A; git -C "$SW" commit -q -m base
(cd "$SW" && bash "$ROOT/skills/plan/scripts/scope-write.sh" plan.md) >/dev/null \
  && ok "scope-write opens a front from the plan" || fail "scope-write failed"
[ -f "$SW/.roadworthy/scope" ] && [ -f "$SW/.roadworthy/gates" ] && [ -f "$SW/.roadworthy/plan.snapshot" ] \
  && ok "it writes the scope, the gates and the snapshot in one act" || fail "scope-write wrote only some of the three"
python3 -c 'import json,sys
s=json.load(open(sys.argv[1]))
need={"ts","plan","plan_name","base_head","scope_globs","gates","digests"}
sys.exit(0 if not (need-set(s)) and set(s["digests"])=={"scope","gates","snapshot_canonical"} else 1)' "$SW/.roadworthy/plan.snapshot" \
  && ok "the snapshot carries the plan, the base HEAD, the globs, the gates and three digests" || fail "snapshot shape"
# Both sections are read as FENCED BLOCKS. A prose bullet is not a command, and close.sh runs each
# gate line with bash -c: accepting bullets would put `- \`cmd\` → expected result` into the gates file.
printf '# P\n## Escopo\n```\nsrc/**\n```\n## Verificação\n- `true` → green\n' > "$TMP/prose.md"
! (cd "$SW" && bash "$ROOT/skills/plan/scripts/scope-write.sh" "$TMP/prose.md" --root "$SW") >/dev/null 2>&1 \
  && ok "a Verification written as prose bullets is refused" || fail "prose accepted as gates"
printf '# P\n## Escopo\n```\n```\n## Verificação\n```\ntrue\n```\n' > "$TMP/empty.md"
! (cd "$SW" && bash "$ROOT/skills/plan/scripts/scope-write.sh" "$TMP/empty.md" --root "$SW") >/dev/null 2>&1 \
  && ok "an empty Scope block is refused: a front with no scope is not a front" || fail "empty scope accepted"
git -C "$SW" add -A; git -C "$SW" commit -q -m 'front open'
# An honest front closes.
echo changed > "$SW/src/a.txt"; git -C "$SW" commit -qam 'inside the scope'
SWOK="$( (cd "$SW" && ROADWORTHY_DATA="$SWD" bash "$ROOT/skills/close/scripts/close.sh") 2>&1 || true )"
printf '%s' "$SWOK" | grep -q '^close: passed' \
  && ok "a front that stayed inside its globs closes" || fail "honest front refused: $SWOK"
# The foundation cannot be edited after approval.
SW2="$TMP/sw2"; SWD2="$TMP/swdata2"; mkdir -p "$SW2/src" "$SWD2"
git -C "$SW2" init -q; git -C "$SW2" config user.email t@t; git -C "$SW2" config user.name t
echo base > "$SW2/src/a.txt"
printf '# P\n## Escopo\n```\nsrc/**\nplan.md\n```\n## Verificação\n```\ntrue\n```\n' > "$SW2/plan.md"
git -C "$SW2" add -A; git -C "$SW2" commit -q -m base
(cd "$SW2" && bash "$ROOT/skills/plan/scripts/scope-write.sh" plan.md) >/dev/null
printf 'false\n' >> "$SW2/.roadworthy/gates"
git -C "$SW2" add -A; git -C "$SW2" commit -q -m 'gates edited by hand'
SWERR="$( (cd "$SW2" && ROADWORTHY_DATA="$SWD2" bash "$ROOT/skills/close/scripts/close.sh") 2>&1 || true )"
printf '%s' "$SWERR" | grep -q 'changed since the front opened' \
  && ok "editing the gates after approval is refused, with both digests named" || fail "hand-edited gates accepted: $SWERR"
# A file touched outside the declared globs surfaces at the closing, even when it was written
# through the shell and the lock never saw it.
SW3="$TMP/sw3"; SWD3="$TMP/swdata3"; mkdir -p "$SW3/src" "$SWD3"
git -C "$SW3" init -q; git -C "$SW3" config user.email t@t; git -C "$SW3" config user.name t
echo base > "$SW3/src/a.txt"
printf '# P\n## Escopo\n```\nsrc/**\nplan.md\n```\n## Verificação\n```\ntrue\n```\n' > "$SW3/plan.md"
git -C "$SW3" add -A; git -C "$SW3" commit -q -m base
(cd "$SW3" && bash "$ROOT/skills/plan/scripts/scope-write.sh" plan.md) >/dev/null
git -C "$SW3" add -A; git -C "$SW3" commit -q -m 'front open'
echo stray > "$SW3/outside.txt"; git -C "$SW3" add -A; git -C "$SW3" commit -q -m 'outside the scope'
SWERR3="$( (cd "$SW3" && ROADWORTHY_DATA="$SWD3" bash "$ROOT/skills/close/scripts/close.sh") 2>&1 || true )"
printf '%s' "$SWERR3" | grep -q 'outside its declared scope' && printf '%s' "$SWERR3" | grep -q 'outside.txt' \
  && ok "a file touched outside the globs refuses the closing, and is named" || fail "stray file closed the front: $SWERR3"
# The plugin's own bookkeeping is not the front's subject: .roadworthy/ never counts as stray.
printf '%s' "$SWERR3" | grep -q '\.roadworthy/' && fail "the closing counted its own bookkeeping as stray" \
  || ok "the plugin's own .roadworthy/ files are not counted against the front"

# ── goldens: the envelope every guard returns, compared key for key ─────────
section "goldens"
# Until now the suite only ever asked whether a fragment appeared in the output. That accepts a
# malformed answer containing the right characters and rejects a correct one formatted otherwise,
# so the SHAPE of what a guard returns -- the contract Claude Code actually consumes -- was never
# pinned by anything. tests/goldens/ holds it, and every guard is measured against it.
GD="$TMP/gold"; mkdir -p "$GD/.roadworthy"; git -C "$GD" init -q

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

CLAUDE_PLUGIN_OPTION_PLANS_DIR="$TMP/goldplans" ; mkdir -p "$TMP/goldplans"
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

# ── privacy: the plugin must carry no personal data ──────────────────────────
section "privacy scan"
# Local Roadworthy state is not a plugin source: close.sh writes a gate's own output there, which
# carries the absolute paths of the machine that ran it, and the snapshot carries the plan's path.
# The ten members are gitignored, and excluded here for the same reason tree-fingerprint.sh leaves
# them out of the fingerprint. Everything else, `.roadworthy/gates` included, is scanned.
LEDGERS='^\./\.roadworthy/(scope|state|plan\.snapshot|overnight|evidence\.jsonl|denials\.jsonl|refutations\.jsonl|preflight\.jsonl|readings\.jsonl|stop-latch/)'
if grep -r -n -E '/Users/[a-z]+|/home/[a-z]+' --include='*' . --exclude-dir=.git --exclude-dir=tests | grep -v 'tests/' | grep -v -E "$LEDGERS" >/dev/null; then
  fail "absolute home path found in plugin sources"
else ok "no absolute home paths"; fi
# No member of the local-state list may be tracked: committing one publishes machine paths, and a
# tracked member dirties the tree at every front, which is what close.sh refuses to run on. The
# gates file is deliberately absent from this list: it is versioned like a test.
LOCAL_STATE='.roadworthy/scope .roadworthy/state .roadworthy/plan.snapshot .roadworthy/overnight
.roadworthy/evidence.jsonl .roadworthy/denials.jsonl .roadworthy/refutations.jsonl
.roadworthy/preflight.jsonl .roadworthy/readings.jsonl .roadworthy/stop-latch'
tracked_state=""
for f in $LOCAL_STATE; do
  git ls-files --error-unmatch "$f" >/dev/null 2>&1 && tracked_state="$tracked_state $f"
done
[ -z "$tracked_state" ] && ok "no local-state file is tracked by git" || fail "tracked local state:$tracked_state"
git ls-files --error-unmatch .roadworthy/gates >/dev/null 2>&1 \
  && ok "the gates file IS tracked (it survives the close; a clone needs it)" \
  || fail "the gates file is not tracked; close.sh refuses to close without it"
git ls-files --error-unmatch bin/__pycache__/rw-metricscpython-311.pyc >/dev/null 2>&1 \
  && fail "a compiled python artefact is tracked" \
  || ok "no compiled python artefact is tracked"

# ── plan pre-flight ──────────────────────────────────────────────────────────
# The gate that replaced the reviewer's attention on things a machine can check. Every assertion
# here is one of those things, in both directions: it must reject the plan that lies and accept
# the plan that does not.
section "plan-preflight (the plan checked mechanically)"
PF="$TMP/pf"; mkdir -p "$PF"
(
  cd "$PF"
  git init -q .; git config user.email t@t; git config user.name t
  printf 'alpha line one\nalpha line two\nalpha line three\n' > a.txt
  printf 'beta line one\nbeta line two\n' > b.txt
  git add -A; git commit -qm base
) >/dev/null 2>&1
PF_HEAD="$(git -C "$PF" rev-parse HEAD)"

# plan_write <file> [extra section text...] — the plan that passes, as the baseline every
# variant below breaks in exactly one place.
plan_write() {
  cat > "$1" <<'PLAN'
# A plan

project: /tmp/pf

## Context

a.txt:2 — `alpha line two`

## Impact sweep

```
git -C . status --porcelain
```

## Scope

```
a.txt
b.txt
c-new.txt
```

**New files declared:** `c-new.txt`.

## Acceptance

| # | WHEN | THE SYSTEM SHALL |
|---|---|---|
| 1 | a | b |
| 2 | c | d |

## Declared corrections

| defect | path | old | new |
|---|---|---|---|
| 1 | `b.txt` | `beta line two` | gone |
PLAN
}
# tr_write <file> <command lines...> — a transcript in the harness's own shape.
tr_write() {
  local out="$1"; shift
  : > "$out"
  for c in "$@"; do
    python3 -c 'import json,sys; print(json.dumps({"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":sys.argv[1]}}]}}))' "$c" >> "$out"
  done
}
# pf <plan> <transcript> [args...] → OUT/RC of a pre-flight run
pf() {
  local p="$1" t="$2"; shift 2
  set +e
  OUT="$(cd "$PF" && bash "$ROOT/skills/plan/scripts/plan-preflight.sh" "$p" --root "$PF" ${t:+--transcript "$t"} "$@" 2>"$TMP/pf.err")"
  RC=$?
  set -e
  ERR="$(cat "$TMP/pf.err")"
}

plan_write "$PF/plan.md"
tr_write "$PF/t.jsonl" 'cat a.txt' 'echo hi
cat b.txt' 'git -C . status --porcelain'
pf "$PF/plan.md" "$PF/t.jsonl"
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'green' \
  && ok "a plan that proves what it claims passes" || fail "green plan rejected: $OUT $ERR"
printf '%s' "$OUT" | grep -q 'files proved read whole 2' \
  && ok "both scope files counted as read whole" || fail "reading count wrong: $OUT"
[ -s "$PF/.roadworthy/preflight.jsonl" ] \
  && ok "the run is recorded in preflight.jsonl" || fail "nothing recorded"

# A newline separates commands exactly as `;` does. Until this was fixed the reading inside a
# multi-line command was invisible and a file read whole counted as never read.
tr_write "$PF/t-nl.jsonl" 'cat a.txt' 'git -C . status --porcelain'
pf "$PF/plan.md" "$PF/t-nl.jsonl"
printf '%s' "$OUT" | grep -q 'b.txt was never read WHOLE' \
  && ok "a file absent from the transcript is named" || fail "unread file not named: $OUT"

# `head -N` is a WINDOW. It used to count here, which is the instrument accepting the very thing
# it exists to refuse.
tr_write "$PF/t-head.jsonl" 'cat a.txt' 'head -20 b.txt' 'git -C . status --porcelain'
pf "$PF/plan.md" "$PF/t-head.jsonl"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'b.txt was never read WHOLE' \
  && ok "head -N does not count as a whole reading" || fail "a window passed as a reading: $OUT"

# Citations are checked by CONTENT. Checking that the line merely exists is what let a false
# citation be signed.
sed 's/alpha line two/alpha line WRONG/' "$PF/plan.md" > "$PF/plan-cit.md"
pf "$PF/plan-cit.md" "$PF/t.jsonl"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'citation a.txt:2 does not match the line' \
  && ok "a citation the line does not sustain is rejected" || fail "false citation passed: $OUT"

# And they are read against the BASE, not against the tree: a correction made during the front
# must not turn the plan's own citation into a false alarm.
printf 'alpha CHANGED\nalpha line two\nalpha line three\n' > "$PF/a.txt"
sed 's/alpha line two`/alpha CHANGED`/; s/a.txt:2/a.txt:1/' "$PF/plan.md" > "$PF/plan-base.md"
pf "$PF/plan-base.md" "$PF/t.jsonl"
[ "$RC" -eq 0 ] && ok "a citation of the tree passes against the tree" || fail "tree citation failed: $OUT"
pf "$PF/plan-base.md" "$PF/t.jsonl" --base "$PF_HEAD"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'citation a.txt:1 does not match' \
  && ok "with a base, the base decides, not the tree" || fail "the base was ignored: $OUT"
pf "$PF/plan.md" "$PF/t.jsonl" --base "$PF_HEAD"
[ "$RC" -eq 0 ] && ok "the plan written against the base is green against the base" || fail "base run red: $OUT"
git -C "$PF" checkout -q -- a.txt
pf "$PF/plan.md" "$PF/t.jsonl" --base no-such-ref
[ "$RC" -ne 0 ] && printf '%s' "$ERR" | grep -q 'does not resolve' \
  && ok "a base that does not resolve is an error, never a silent fall back" || fail "bad base tolerated: $ERR"

# Scope: a path that does not exist must be declared as a new file.
sed 's/^b\.txt$/nowhere.txt/' "$PF/plan.md" > "$PF/plan-scope.md"
pf "$PF/plan-scope.md" "$PF/t.jsonl"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'nowhere.txt does not exist and is not declared' \
  && ok "an invented scope path is named" || fail "invented path passed: $OUT"
printf '%s' "$OUT" | grep -q 'c-new.txt does not exist' \
  && fail "a declared new file was treated as missing" || ok "a declared new file is exempt"

# Acceptance numbering: 1..N, no gap, no repeat.
sed 's/^| 2 | c | d |$/| 4 | c | d |/' "$PF/plan.md" > "$PF/plan-acc.md"
pf "$PF/plan-acc.md" "$PF/t.jsonl"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'acceptance numbers are not' \
  && ok "a gap in the acceptance numbering is caught" || fail "numbering gap passed: $OUT"

# Declared corrections: the literal must be there BEFORE the work and gone at the close. This is
# the rule that turns "I fixed it" from a sentence into something a machine checks.
sed 's/`beta line two`/`beta line NEVER`/' "$PF/plan.md" > "$PF/plan-corr.md"
pf "$PF/plan-corr.md" "$PF/t.jsonl"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'is not the case' \
  && ok "a correction of text that is not there is rejected" || fail "phantom correction passed: $OUT"
pf "$PF/plan.md" "$PF/t.jsonl" --closing
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'correction NOT DONE: b.txt' \
  && ok "at the close, an undone correction is named" || fail "undone correction passed: $OUT"
printf 'beta line one\nbeta DONE\n' > "$PF/b.txt"
pf "$PF/plan.md" "$PF/t.jsonl" --closing
[ "$RC" -eq 0 ] && ok "at the close, the correction actually made passes" || fail "done correction rejected: $OUT"
git -C "$PF" checkout -q -- b.txt

# An impact sweep command that was never run is a sweep that was narrated.
tr_write "$PF/t-nosweep.jsonl" 'cat a.txt' 'cat b.txt'
pf "$PF/plan.md" "$PF/t-nosweep.jsonl"
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'not in the session transcript' \
  && ok "a sweep command that was never run is named" || fail "narrated sweep passed: $OUT"

# And with no transcript at all, nothing about reading can be proved -- which is the whole point.
pf "$PF/plan.md" ""
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'no transcript given' \
  && ok "without a transcript the pre-flight refuses to take the plan's word" || fail "no-transcript passed: $OUT"

# ── plan-review-gate: the pre-flight is the criterion ────────────────────────
# The inversion of 0.6.0. The reviewer goes back to the diff (principle 4 of this plugin always
# said diff), and what guards the PLAN is the mechanical check. These assertions measure that the
# mode changes the CRITERION and never the on/off switch: an option that silently disabled the
# gate is exactly how a fence dies unnoticed.
section "plan-review-gate (plan_gate=preflight)"
PG="$TMP/pg"; PGP="$PG/plans"; PGR="$PG/repo"; mkdir -p "$PGP" "$PGR"
(
  cd "$PGR"
  git init -q .; git config user.email t@t; git config user.name t
  printf 'one\ntwo\n' > src.txt
  git add -A; git commit -qm base
) >/dev/null 2>&1
PGR_REAL="$(cd "$PGR" && pwd -P)"
cat > "$PGP/good.md" <<PLANEOF
# A plan

project: $PGR_REAL

## Scope

\`\`\`
src.txt
\`\`\`

## Acceptance

| # | WHEN | THE SYSTEM SHALL |
|---|---|---|
| 1 | a | b |
PLANEOF
python3 -c 'import json,sys; print(json.dumps({"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cat src.txt"}}]}}))' > "$PG/t.jsonl"
export CLAUDE_PLUGIN_OPTION_PLANS_DIR="$PGP"
PG_EVENT="{\"tool_name\":\"ExitPlanMode\",\"tool_input\":{},\"cwd\":\"$PGR\",\"transcript_path\":\"$PG/t.jsonl\"}"

run_hook plan-review-gate "$PG_EVENT"
! denied && ok "in preflight mode a green plan passes with NO review at all" || fail "green plan denied: $OUT"

# The whole point: the criterion changed, the switch did not.
sed -i.bak 's/^| 1 | a | b |$/| 3 | a | b |/' "$PGP/good.md"; rm -f "$PGP/good.md.bak"
run_hook plan-review-gate "$PG_EVENT"
denied && printf '%s' "$OUT" | grep -q 'pre-flight is red' \
  && ok "a red pre-flight denies the submission" || fail "red pre-flight submitted: $OUT"
printf '%s' "$OUT" | grep -q 'acceptance numbers are not' \
  && ok "the denial carries what the pre-flight found" || fail "denial without the finding: $OUT"
sed -i.bak 's/^| 3 | a | b |$/| 1 | a | b |/' "$PGP/good.md"; rm -f "$PGP/good.md.bak"

# A plan whose scope was never read whole is the case this front exists for.
run_hook plan-review-gate "{\"tool_name\":\"ExitPlanMode\",\"tool_input\":{},\"cwd\":\"$PGR\",\"transcript_path\":\"$PG/empty.jsonl\"}"
denied && printf '%s' "$OUT" | grep -q 'no transcript given' \
  && ok "without a transcript the gate refuses to take the plan's word" || fail "no-transcript submitted: $OUT"

# The boolean switch is untouched by the new option: off is off, in every mode.
CLAUDE_PLUGIN_OPTION_PLAN_REVIEW_REQUIRED=false run_hook plan-review-gate "$PG_EVENT"
! denied && [ "$RC" -eq 0 ] && ok "plan_review_required=false still silences the gate in preflight mode" \
  || fail "the boolean switch stopped working: $OUT"

# A mode nobody declared must not be guessed at.
CLAUDE_PLUGIN_OPTION_PLAN_GATE=sometimes run_hook plan-review-gate "$PG_EVENT"
denied && printf '%s' "$OUT" | grep -q "plan_gate is 'sometimes'" \
  && ok "an unknown plan_gate value denies, naming it" || fail "unknown mode tolerated: $OUT"

# In review mode the pre-flight is not consulted at all: the old path stays exactly as it was.
CLAUDE_PLUGIN_OPTION_PLAN_GATE=review run_hook plan-review-gate "$PG_EVENT"
denied && printf '%s' "$OUT" | grep -q 'no review for the current plan' \
  && ok "review mode still demands the reviewer, and only the reviewer" || fail "review mode changed: $OUT"

# And in both modes together, a green pre-flight is not enough on its own.
CLAUDE_PLUGIN_OPTION_PLAN_GATE=both run_hook plan-review-gate "$PG_EVENT"
denied && ok "both: a green pre-flight does not replace the verdict" || fail "both mode passed without a review: $OUT"
unset CLAUDE_PLUGIN_OPTION_PLANS_DIR

# ── official validation ──────────────────────────────────────────────────────
section "claude plugin validate"
if command -v claude >/dev/null 2>&1; then
  claude plugin validate . --strict >/dev/null 2>"$TMP/v" && ok "claude plugin validate --strict" || { fail "claude plugin validate"; cat "$TMP/v"; }
else
  echo "  [SKIP] claude CLI not installed"
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then echo "RESULT: gate clean"; else echo "RESULT: $FAIL failure(s)"; exit 1; fi
